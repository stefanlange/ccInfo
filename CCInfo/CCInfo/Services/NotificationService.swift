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

    // Track last notified update version to avoid duplicate update notifications
    private var hasNotifiedForUpdate: String?

    enum WindowType: String {
        case fiveHour = "5-Hour"
        case sevenDay = "Weekly"
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
    func checkThresholds(usage: UsageData) {
        // Reset thresholds that are no longer applicable (allows re-notification after reset)
        notifiedFiveHour = notifiedFiveHour.filter { Double($0) <= usage.fiveHour.utilization }
        notifiedSevenDay = notifiedSevenDay.filter { Double($0) <= usage.sevenDay.utilization }

        // Check 5-hour window
        checkAndNotify(
            window: .fiveHour,
            utilization: usage.fiveHour.utilization,
            resetTime: usage.fiveHour.formattedTimeUntilReset
        )

        // Check 7-day window
        checkAndNotify(
            window: .sevenDay,
            utilization: usage.sevenDay.utilization,
            resetTime: usage.sevenDay.formattedTimeUntilReset
        )
    }

    private func checkAndNotify(window: WindowType, utilization: Double, resetTime: String?) {
        let thresholds = [80, 95]

        for threshold in thresholds where utilization >= Double(threshold) {
            let alreadyNotified = switch window {
            case .fiveHour: notifiedFiveHour.contains(threshold)
            case .sevenDay: notifiedSevenDay.contains(threshold)
            }

            guard !alreadyNotified else { continue }

            sendNotification(window: window, threshold: threshold, utilization: utilization, resetTime: resetTime)

            switch window {
            case .fiveHour: notifiedFiveHour.insert(threshold)
            case .sevenDay: notifiedSevenDay.insert(threshold)
            }
        }
    }

    private func sendNotification(window: WindowType, threshold: Int, utilization: Double, resetTime: String?) {
        let content = UNMutableNotificationContent()

        let severity = threshold >= 95 ? "⚠️" : "⚡️"
        content.title = "\(severity) \(window.rawValue) Limit: \(Int(utilization))%"

        if let resetTime {
            content.body = String(
                localized: "Your \(window.rawValue.lowercased()) usage is at \(Int(utilization))%. Resets in \(resetTime)."
            )
        } else {
            content.body = String(
                localized: "Your \(window.rawValue.lowercased()) usage is at \(Int(utilization))%."
            )
        }

        content.sound = threshold >= 95 ? .default : nil
        content.interruptionLevel = threshold >= 95 ? .timeSensitive : .active

        let identifier = "usage-\(window.rawValue)-\(threshold)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        // Spawn detached task for notification (fire-and-forget is acceptable for notifications)
        Task { @MainActor in
            do {
                try await notificationCenter.add(request)
                logger.info("Sent notification for \(window.rawValue) at \(threshold)%")
            } catch {
                logger.error("Failed to send notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Update Notification

    /// Send a notification when a new app update is available
    func sendUpdateNotification(version: String) {
        guard hasNotifiedForUpdate != version else { return }
        hasNotifiedForUpdate = version

        let content = UNMutableNotificationContent()
        content.title = "ccInfo"
        content.body = String(localized: "notification.updateAvailable \(version)")
        content.interruptionLevel = .active

        let request = UNNotificationRequest(identifier: "update-available", content: content, trigger: nil)

        Task { @MainActor in
            do {
                try await notificationCenter.add(request)
                logger.info("Sent update notification for version \(version)")
            } catch {
                logger.error("Failed to send update notification: \(error.localizedDescription)")
            }
        }
    }

    /// Reset notification state when user signs out or app restarts
    func resetAllThresholds() {
        notifiedFiveHour.removeAll()
        notifiedSevenDay.removeAll()
    }
}
