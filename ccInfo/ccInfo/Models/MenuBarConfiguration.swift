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

enum AppStorageKeys {
    static let menuBarSlot1 = "menuBarSlot1"
    static let menuBarSlot2 = "menuBarSlot2"
    static let launchAtLogin = "launchAtLogin"
    static let refreshInterval = "refreshInterval"
    static let sessionActivityThreshold = "sessionActivityThreshold"
    static let statisticsPeriod = "statisticsPeriod"

    enum Defaults {
        static let launchAtLogin: Bool = false
        static let refreshInterval: Double = 30
        static let sessionActivityThreshold: Double = 600
        static let statisticsPeriod: StatisticsPeriod = .today
        static let menuBarSlot1: MenuBarSlot = .fiveHour
        static let menuBarSlot2: MenuBarSlot = .weeklyLimit
    }
}
