import Foundation

struct UsageResponse: Codable, Sendable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDayOpus: UsageWindow?
    let sevenDaySonnet: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
    }
}

struct UsageWindow: Codable, Sendable {
    let utilization: Double
    let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct UsageData: Sendable {
    let fiveHour: WindowUsage
    let sevenDay: WindowUsage
    let sevenDaySonnet: WindowUsage?
    let sevenDayOpus: WindowUsage?
    let fetchedAt: Date

    struct WindowUsage: Sendable {
        let utilization: Double
        let resetsAt: Date?

        // MARK: - Cached Formatters
        private static let durationFormatter: DateComponentsFormatter = {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute]
            formatter.unitsStyle = .abbreviated
            formatter.zeroFormattingBehavior = .dropLeading
            formatter.calendar = Calendar.current
            return formatter
        }()

        private static let resetDateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("EddMMHHmm")
            return formatter
        }()

        var formattedTimeUntilReset: String? {
            guard let resetsAt, resetsAt.timeIntervalSinceNow > 0 else { return nil }
            return Self.durationFormatter.string(from: resetsAt.timeIntervalSinceNow)
        }

        var formattedResetDate: String? {
            guard let resetsAt, resetsAt.timeIntervalSinceNow > 0 else { return nil }
            return Self.resetDateFormatter.string(from: resetsAt)
        }
    }

    init(from response: UsageResponse) {
        self.fiveHour = WindowUsage(
            utilization: response.fiveHour?.utilization ?? 0,
            resetsAt: response.fiveHour?.resetsAt
        )
        self.sevenDay = WindowUsage(
            utilization: response.sevenDay?.utilization ?? 0,
            resetsAt: response.sevenDay?.resetsAt
        )
        self.sevenDaySonnet = response.sevenDaySonnet.map {
            WindowUsage(utilization: $0.utilization, resetsAt: $0.resetsAt)
        }
        self.sevenDayOpus = response.sevenDayOpus.map {
            WindowUsage(utilization: $0.utilization, resetsAt: $0.resetsAt)
        }
        self.fetchedAt = Date()
    }
}
