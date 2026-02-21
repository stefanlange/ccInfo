import Foundation

/// A single data point in the 5-hour usage history timeline.
struct UsageDataPoint: Codable, Sendable {
    /// Timestamp when this data point was captured
    let timestamp: Date

    /// Usage percentage (0-100)
    let usage: Int

    /// Indicates a gap in the timeline (e.g., app was closed)
    let isGap: Bool

    init(timestamp: Date, usage: Int, isGap: Bool = false) {
        self.timestamp = timestamp
        self.usage = usage
        self.isGap = isGap
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case timestamp
        case usage
        case isGap
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let epochTime = try container.decode(TimeInterval.self, forKey: .timestamp)
        self.timestamp = Date(timeIntervalSince1970: epochTime)
        self.usage = try container.decode(Int.self, forKey: .usage)
        self.isGap = try container.decode(Bool.self, forKey: .isGap)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Int(timestamp.timeIntervalSince1970), forKey: .timestamp)
        try container.encode(usage, forKey: .usage)
        try container.encode(isGap, forKey: .isGap)
    }
}
