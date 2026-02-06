import Foundation

// MARK: - Statistics Period

enum StatisticsPeriod: String, CaseIterable, Sendable {
    case session, today, thisWeek, thisMonth

    var displayName: String {
        switch self {
        case .session:   return String(localized: "Session")
        case .today:     return String(localized: "Today")
        case .thisWeek:  return String(localized: "This Week")
        case .thisMonth: return String(localized: "This Month")
        }
    }

    /// Nil for .session (= no date filter, single file)
    func periodStart(calendar: Calendar = .current) -> Date? {
        let now = Date()
        switch self {
        case .session:   return nil
        case .today:     return calendar.startOfDay(for: now)
        case .thisWeek:  return calendar.dateInterval(of: .weekOfYear, for: now)?.start
        case .thisMonth: return calendar.dateInterval(of: .month, for: now)?.start
        }
    }
}

// MARK: - Claude Model Pricing

/// Represents Claude model variants with their respective API pricing
enum ClaudeModel: String, Sendable, CaseIterable {
    case opus = "opus"
    case sonnet = "sonnet"
    case haiku = "haiku"
    case unknown = "unknown"

    /// Pricing per million tokens
    struct Pricing: Sendable {
        let input: Double
        let output: Double
        let cacheWrite: Double
        let cacheRead: Double
    }

    var pricing: Pricing {
        switch self {
        case .opus:
            // Claude Opus 4.5: $15/$75 per MTok
            return Pricing(input: 15.0, output: 75.0, cacheWrite: 18.75, cacheRead: 1.50)
        case .sonnet:
            // Claude Sonnet 4.5: $3/$15 per MTok (same for standard and 1M context variants)
            return Pricing(input: 3.0, output: 15.0, cacheWrite: 3.75, cacheRead: 0.30)
        case .haiku:
            // Claude Haiku 4.5: $1/$5 per MTok
            return Pricing(input: 1.0, output: 5.0, cacheWrite: 1.25, cacheRead: 0.10)
        case .unknown:
            // Default to Sonnet pricing
            return Pricing(input: 3.0, output: 15.0, cacheWrite: 3.75, cacheRead: 0.30)
        }
    }

    var displayName: String {
        switch self {
        case .opus: return "Opus"
        case .sonnet: return "Sonnet"
        case .haiku: return "Haiku"
        case .unknown: return "Unknown"
        }
    }

    /// Extended display name with context information
    func displayName(extended: Bool) -> String {
        switch self {
        case .sonnet:
            return extended ? "Sonnet 1M" : "Sonnet"
        default:
            return displayName
        }
    }

    /// Initialize from model ID string (e.g., "claude-sonnet-4-5-20250929")
    init(fromModelId modelId: String?) {
        guard let modelId = modelId?.lowercased() else {
            self = .unknown
            return
        }

        if modelId.contains("opus") {
            self = .opus
        } else if modelId.contains("sonnet") {
            self = .sonnet
        } else if modelId.contains("haiku") {
            self = .haiku
        } else {
            self = .unknown
        }
    }
}

// MARK: - JSONL Parsing

struct JSONLEntry: Codable, Sendable {
    let type: String?
    let sessionId: String?
    let timestamp: Date?
    let message: Message?
    let model: String?

    struct Message: Codable, Sendable {
        let role: String?
        let usage: TokenUsage?
        let model: String?
    }

    struct TokenUsage: Codable, Sendable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
        }

        var totalInputTokens: Int {
            (inputTokens ?? 0) + (cacheCreationInputTokens ?? 0) + (cacheReadInputTokens ?? 0)
        }
    }

    /// Extract model from entry (checks both top-level and message-level)
    var detectedModel: ClaudeModel {
        ClaudeModel(fromModelId: model ?? message?.model)
    }
}

struct SessionData: Sendable {
    let sessionId: String?
    let tokens: TokenStats
    let models: Set<ClaudeModel>  // All models used in this session

    /// Estimated cost based on per-entry model pricing
    var estimatedCost: Double {
        tokens.cost
    }

    struct TokenStats: Sendable {
        let input: Int
        let output: Int
        let cacheCreation: Int
        let cacheRead: Int
        let cost: Double

        var totalInput: Int { input + cacheCreation + cacheRead }
        var totalTokens: Int { input + output + cacheCreation + cacheRead }

        static var zero: TokenStats {
            TokenStats(input: 0, output: 0, cacheCreation: 0, cacheRead: 0, cost: 0)
        }

        /// Combine token stats (cumulative across all models)
        static func + (lhs: TokenStats, rhs: TokenStats) -> TokenStats {
            return TokenStats(
                input: lhs.input + rhs.input,
                output: lhs.output + rhs.output,
                cacheCreation: lhs.cacheCreation + rhs.cacheCreation,
                cacheRead: lhs.cacheRead + rhs.cacheRead,
                cost: lhs.cost + rhs.cost
            )
        }
    }
}

struct ContextWindow: Sendable {
    // Context window constants
    private enum Constants {
        static let standardMaxTokens = 200_000
        static let extendedMaxTokens = 1_000_000
        static let autoCompactThreshold = 45_000
        // Heuristic: if tokens exceed this, assume 1M context mode
        static let extendedContextThreshold = 180_000
    }

    let currentTokens: Int
    let activeModel: ClaudeModel?

    /// Detected maximum tokens (200k standard or 1M extended)
    var maxTokens: Int {
        isExtendedContext ? Constants.extendedMaxTokens : Constants.standardMaxTokens
    }

    /// True if we detect extended (1M) context mode via heuristic
    var isExtendedContext: Bool {
        currentTokens > Constants.extendedContextThreshold
    }

    var utilization: Double {
        let maxValue = Swift.max(1, maxTokens) // Prevent division by zero
        let currentValue = Swift.max(0, currentTokens) // Clamp negative values
        return Double(currentValue) / Double(maxValue) * 100
    }

    var isNearAutoCompact: Bool {
        // Autocompact threshold applies relative to the detected max
        currentTokens >= maxTokens - Constants.autoCompactThreshold
    }

    init(currentTokens: Int, activeModel: ClaudeModel? = nil) {
        self.currentTokens = currentTokens
        self.activeModel = activeModel
    }
}
