import Foundation

enum MenuBarSlot: String, CaseIterable, Sendable, Codable {
    case contextWindow
    case fiveHour
    case weeklyLimit
    case sonnetWeekly

    var displayName: String {
        switch self {
        case .contextWindow:
            return String(localized: "Context Window")
        case .fiveHour:
            return String(localized: "5-Hour Window")
        case .weeklyLimit:
            return String(localized: "Weekly Limit")
        case .sonnetWeekly:
            return String(localized: "Sonnet Weekly")
        }
    }

    static let defaultSlot1: MenuBarSlot = .fiveHour
    static let defaultSlot2: MenuBarSlot = .weeklyLimit
}

enum MenuBarConfiguration {
    enum StorageKeys {
        static let slot1 = "menuBarSlot1"
        static let slot2 = "menuBarSlot2"
    }
}
