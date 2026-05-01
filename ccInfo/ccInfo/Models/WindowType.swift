import Foundation

/// Models the kind of usage window surfaced by notifications (rolling 5-hour vs weekly).
///
/// The localized helpers below intentionally call `String(localized:)` and return `String`,
/// diverging from implicit-`LocalizedStringKey` convention used elsewhere in
/// the project. This is required because `UNMutableNotificationContent.title` and `.body`
/// are typed as `String` and do not accept `LocalizedStringKey`.
enum WindowType: String {
    case fiveHour = "5-Hour"
    case sevenDay = "Weekly"

    // Note: string also used in MenuBarView.swift and MenuBarConfiguration.swift.
    var localizedLimitLabel: String {
        switch self {
        case .fiveHour: return String(localized: "5-Hour Limit")
        case .sevenDay: return String(localized: "Weekly Limit")
        }
    }

    var localizedSentenceForm: String {
        switch self {
        case .fiveHour: return String(localized: "5-hour")
        case .sevenDay: return String(localized: "weekly")
        }
    }
}
