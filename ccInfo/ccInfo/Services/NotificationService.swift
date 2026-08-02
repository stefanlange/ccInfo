import Foundation
@preconcurrency import UserNotifications
import OSLog

/// Service for managing usage threshold notifications
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private let logger = Logger(subsystem: "com.ccinfo.app", category: "Notifications")
    private let notificationCenter = UNUserNotificationCenter.current()

    // Track which thresholds have already triggered to avoid duplicate notifications
    private var notifiedFiveHour: Set<Int> = []
    private var notifiedSevenDay: Set<Int> = []
    private var notifiedBurnRate = false

    // What each window's reset notification is currently scheduled for, so an
    // unchanged window does not re-register the same request on every poll.
    private var lastScheduledReset: [WindowType: (resetsAt: Date, utilization: Int)] = [:]

    private init() {}

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
            if granted {
                logger.info("Notification permission granted")
            } else {
                logger.info("Notification permission denied")
            }
            return granted
        } catch {
            logger.error("Failed to request notification permission: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Threshold Checking

    /// Check usage and send notifications if thresholds are crossed
    func checkThresholds(usage: UsageData) async {
        // Reset thresholds that are no longer applicable (allows re-notification after reset)
        notifiedFiveHour = notifiedFiveHour.filter { Double($0) <= usage.fiveHour.utilization }
        notifiedSevenDay = notifiedSevenDay.filter { Double($0) <= usage.sevenDay.utilization }

        await checkAndNotify(
            window: .fiveHour,
            utilization: usage.fiveHour.utilization,
            resetTime: usage.fiveHour.formattedTimeUntilReset
        )

        await checkAndNotify(
            window: .sevenDay,
            utilization: usage.sevenDay.utilization,
            resetTime: usage.sevenDay.formattedTimeUntilReset
        )
    }

    private func checkAndNotify(window: WindowType, utilization: Double, resetTime: String?) async {
        let thresholds = [80, 95]

        for threshold in thresholds where utilization >= Double(threshold) {
            let alreadyNotified = switch window {
            case .fiveHour: notifiedFiveHour.contains(threshold)
            case .sevenDay: notifiedSevenDay.contains(threshold)
            }

            guard !alreadyNotified else { continue }

            await sendNotification(window: window, threshold: threshold, utilization: utilization, resetTime: resetTime)

            switch window {
            case .fiveHour: notifiedFiveHour.insert(threshold)
            case .sevenDay: notifiedSevenDay.insert(threshold)
            }
        }
    }

    private func sendNotification(window: WindowType, threshold: Int, utilization: Double, resetTime: String?) async {
        let content = UNMutableNotificationContent()

        let severity = threshold >= 95 ? "⚠️" : "⚡️"
        content.title = "\(severity) \(window.localizedLimitLabel): \(Int(utilization))%"

        if let resetTime {
            content.body = String(
                localized: "Your \(window.localizedSentenceForm) usage is at \(Int(utilization))%. Resets in \(resetTime)."
            )
        } else {
            content.body = String(
                localized: "Your \(window.localizedSentenceForm) usage is at \(Int(utilization))%."
            )
        }

        content.sound = threshold >= 95 ? .default : nil
        content.interruptionLevel = threshold >= 95 ? .timeSensitive : .active

        let identifier = "usage-\(window.rawValue)-\(threshold)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        do {
            try await notificationCenter.add(request)
            logger.info("Sent notification for \(window.rawValue) at \(threshold)%")
        } catch {
            logger.error("Failed to send notification: \(error.localizedDescription)")
        }
    }

    // MARK: - Burn Rate

    /// Check burn rate and fire a one-shot notification when exhaustion is first predicted.
    /// Resets automatically when the danger passes so a future spike can re-trigger.
    func checkBurnRate(history: [UsageDataPoint], usage: UsageData) async {
        guard let prediction = BurnRateCalculator.predict(
            history: history,
            currentUtilization: usage.fiveHour.utilization,
            resetsAt: usage.fiveHour.resetsAt
        ) else {
            // Only treat a missing prediction as "danger passed" when history actually exists.
            // With empty history (startup, pre-first-record), predict() returns nil for a
            // different reason and we must not reset the one-shot flag.
            if !history.isEmpty {
                notifiedBurnRate = false
            }
            return
        }
        guard !notifiedBurnRate else { return }
        notifiedBurnRate = true

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Burn rate warning")
        let timeLabel = prediction.formattedTimeUntilLimit
        content.body = String(localized: "At current pace, token limit reached in \(timeLabel).")
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: "usage-burnrate",
            content: content,
            trigger: nil
        )
        do {
            try await notificationCenter.add(request)
            logger.info("Sent burn rate notification (limit in \(timeLabel))")
        } catch {
            logger.error("Failed to send burn rate notification: \(error.localizedDescription)")
        }
    }

    // MARK: - Window Reset Notifications

    /// Schedule (or cancel) the "window reset" notification for `window`.
    ///
    /// Uses `UNTimeIntervalNotificationTrigger` so it survives app sleep/restart
    /// (the system delivers it even if ccInfo isn't running at fire time), unlike
    /// the `trigger: nil` (immediate) requests used elsewhere in this file. An
    /// interval counts down from now rather than matching calendar fields, which
    /// would drift by an hour across a DST change on the weekly window.
    ///
    /// `requiresUsage` gates the 5-hour window on the user having consumed
    /// something in it, so an untouched window stays silent. The weekly window
    /// passes false: a week boundary is worth knowing about either way.
    func checkWindowReset(_ window: WindowType, usage: UsageData.WindowUsage, requiresUsage: Bool) async {
        guard let resetsAt = usage.resetsAt, resetsAt > Date(),
              !requiresUsage || usage.utilization > 0 else {
            cancelPendingReset(window)
            lastScheduledReset[window] = nil
            return
        }

        let utilization = Int(usage.utilization)
        // Re-adding replaces the pending request, which is how the body stays
        // current. Skip it while nothing has changed, so an untouched window
        // does not re-register every poll for hours on end.
        guard lastScheduledReset[window]?.resetsAt != resetsAt
                || lastScheduledReset[window]?.utilization != utilization else { return }

        await scheduleReset(window, at: resetsAt, utilization: utilization)
        lastScheduledReset[window] = (resetsAt, utilization)
    }

    private func scheduleReset(_ window: WindowType, at resetsAt: Date, utilization: Int) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(window.localizedLimitLabel) Reset")
        content.body = String(
            localized: "You used \(utilization)% of your previous \(window.localizedSentenceForm) window. Fresh capacity is available now."
        )
        content.sound = .default
        content.interruptionLevel = .active

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, resetsAt.timeIntervalSinceNow), repeats: false
        )
        let request = UNNotificationRequest(
            identifier: resetIdentifier(for: window), content: content, trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            logger.info("Scheduled \(window.rawValue, privacy: .public) reset notification for \(resetsAt, privacy: .public) at \(utilization, privacy: .public)%")
        } catch {
            logger.error("Failed to schedule reset notification: \(error.localizedDescription)")
        }
    }

    private func cancelPendingReset(_ window: WindowType) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [resetIdentifier(for: window)])
    }

    private func resetIdentifier(for window: WindowType) -> String {
        "usage-reset-\(window.rawValue)"
    }

    /// Reset notification state when user signs out or app restarts
    func resetAllThresholds() {
        notifiedFiveHour.removeAll()
        notifiedSevenDay.removeAll()
        notifiedBurnRate = false
        for window in WindowType.allCases {
            cancelPendingReset(window)
        }
        lastScheduledReset.removeAll()
    }
}
