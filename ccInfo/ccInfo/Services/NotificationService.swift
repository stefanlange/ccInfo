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

    // The reset the notified thresholds above belong to, so a rotation can clear them
    // while a dip in utilization cannot. See `clearThresholdsIfRotated`.
    private var thresholdWindowReset: [WindowType: Date] = [:]

    /// Floor for the trigger interval. `UNTimeIntervalNotificationTrigger` raises on
    /// an interval of zero or less, and a reset this close is about to rotate anyway.
    private static let minimumResetLead: TimeInterval = 60

    /// How far apart two reset times must be to describe different windows.
    ///
    /// `resets_at` carries the API's own sub-second clock, so consecutive responses
    /// name the same instant with slightly different values (measured: the decoded
    /// `Date` moved across all five polling intervals while utilization held still).
    /// The deviation oscillates rather than accumulating; measured against a reference
    /// 44 minutes old, both windows sat within a second of it. A tolerance this size
    /// therefore holds indefinitely, while a real rotation moves the reset by hours
    /// and stays clearly distinguishable.
    private static let resetMatchTolerance: TimeInterval = 60

    /// Whether `scheduled` and `candidate` describe the same reset.
    private static func isSameReset(_ scheduled: Date?, _ candidate: Date) -> Bool {
        guard let scheduled else { return false }
        return abs(scheduled.timeIntervalSince(candidate)) < resetMatchTolerance
    }

    /// When the reset notification currently registered for `window` will fire, if any.
    ///
    /// Asks the notification centre rather than tracking it in a property: pending
    /// requests outlive the process, so in-memory bookkeeping reads as "nothing
    /// registered" after every relaunch and re-registers a request that is already
    /// there and still correct. Each re-register is shown to the user.
    private func pendingResetDate(for window: WindowType) async -> Date? {
        let identifier = resetIdentifier(for: window)
        let pending = await notificationCenter.pendingNotificationRequests()
        guard let request = pending.first(where: { $0.identifier == identifier }),
              let trigger = request.trigger as? UNTimeIntervalNotificationTrigger else { return nil }
        return trigger.nextTriggerDate()
    }

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
        clearThresholdsIfRotated(.fiveHour, resetsAt: usage.fiveHour.resetsAt)
        clearThresholdsIfRotated(.sevenDay, resetsAt: usage.sevenDay.resetsAt)

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

    /// Re-arm `window`'s thresholds when the window itself has rotated.
    ///
    /// Re-arming used to key off utilization falling back below a threshold, on the
    /// assumption that only a reset can lower it. Utilization is not that dependable:
    /// the API reports it rounded, and the weekly figure can recede as older usage
    /// ages out, so a value resting near a threshold re-armed it and notified again on
    /// the next crossing. The reset time is what actually identifies a window, so a
    /// rotation clears the set and a mere dip leaves it alone.
    ///
    /// Without a reset time a window cannot be told apart, and the quiet choice is to
    /// keep the set as it stands rather than risk notifying twice for one window.
    private func clearThresholdsIfRotated(_ window: WindowType, resetsAt: Date?) {
        guard let resetsAt, !Self.isSameReset(thresholdWindowReset[window], resetsAt) else { return }

        switch window {
        case .fiveHour: notifiedFiveHour.removeAll()
        case .sevenDay: notifiedSevenDay.removeAll()
        }
        thresholdWindowReset[window] = resetsAt
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
    /// Registered once per window and then left alone. Adding a request replaces any
    /// pending one under the same identifier, and macOS shows that replacement to the
    /// user instead of swapping it silently, so a re-register costs a delivery. That
    /// is why the body carries no usage figure: keeping a percentage current would
    /// mean re-registering as the number moves, which is what made 1.15.0 deliver a
    /// copy on every poll. Nothing in the text changes over the window's life, so the
    /// request can be written far ahead and still be right when it fires.
    ///
    /// `requiresUsage` gates the 5-hour window on the user having consumed
    /// something in it, so an untouched window stays silent. The weekly window
    /// passes false: a week boundary is worth knowing about either way.
    func checkWindowReset(_ window: WindowType, usage: UsageData.WindowUsage, requiresUsage: Bool) async {
        let pendingReset = await pendingResetDate(for: window)

        // Without a reset time there is nothing this notification could announce.
        guard let resetsAt = usage.resetsAt else {
            cancelPendingReset(window)
            return
        }

        // Already registered for this reset, either earlier in this run or by a
        // previous one. Leave it alone: it is still correct, and re-adding it would
        // reach the user a second time.
        if Self.isSameReset(pendingReset, resetsAt) { return }

        // An untouched window has nothing to announce, so nothing gets registered.
        // A request already standing is deliberately left alone: the API can report a
        // rotated window's utilization of 0 while `resets_at` still names the reset
        // that is happening right now (see ClaudeAPIClient's stale-value handling),
        // and cancelling on that reading would delete the very notification the user
        // is owed, moments before it fires.
        guard !requiresUsage || usage.utilization > 0 else { return }

        // Measure the lead once and pass it down: re-reading it when building the
        // trigger could yield a smaller, in the limit non-positive, value, and
        // UNTimeIntervalNotificationTrigger raises on an interval of zero or less.
        let lead = resetsAt.timeIntervalSinceNow

        // Too close to aim at. Any pending request stays standing for the same reason
        // as above: this is the branch a rotating window passes through.
        guard lead >= Self.minimumResetLead else { return }

        await scheduleReset(window, at: resetsAt, lead: lead)
    }

    private func scheduleReset(_ window: WindowType, at resetsAt: Date, lead: TimeInterval) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(window.localizedLimitLabel) Reset")
        // The title names which window reset, so the body only states what follows
        // from it. Deliberately free of any figure: a value that moves would have to
        // be revised, and revising means re-registering, which the user sees.
        content.body = String(localized: "The full allowance is available again.")
        content.sound = .default
        content.interruptionLevel = .active

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: lead, repeats: false)
        let request = UNNotificationRequest(
            identifier: resetIdentifier(for: window), content: content, trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            logger.info("Scheduled \(window.rawValue, privacy: .public) reset notification for \(resetsAt, privacy: .public)")
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
        thresholdWindowReset.removeAll()
        // Signing out invalidates the pending resets too; they would otherwise fire
        // for an account this install no longer watches.
        for window in WindowType.allCases {
            cancelPendingReset(window)
        }
    }
}
