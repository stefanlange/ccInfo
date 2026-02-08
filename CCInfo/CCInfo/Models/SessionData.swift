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

/// Represents Claude model variants for UI grouping
enum ClaudeModel: String, Sendable, CaseIterable {
    case opus = "opus"
    case sonnet = "sonnet"
    case haiku = "haiku"
    case unknown = "unknown"

    var displayName: String {
        switch self {
        case .opus: return "Opus"
        case .sonnet: return "Sonnet"
        case .haiku: return "Haiku"
        case .unknown: return "Unknown"
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

    /// Extract raw model ID string from entry (checks both top-level and message-level)
    var rawModelId: String? {
        model ?? message?.model
    }
}

struct SessionData: Sendable {
    let sessionId: String?
    let tokens: TokenStats
    let models: Set<ModelIdentifier>  // All models used in this session

    /// Estimated cost based on per-entry model pricing
    var estimatedCost: Double {
        tokens.cost
    }

    /// True if any model in this session used fallback pricing
    var isCostEstimated: Bool {
        models.contains { $0.isFallback }
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
    let activeModel: ModelIdentifier?

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

    init(currentTokens: Int, activeModel: ModelIdentifier? = nil) {
        self.currentTokens = currentTokens
        self.activeModel = activeModel
    }
}

struct AgentContext: Sendable, Identifiable {
    let agentId: String
    let contextWindow: ContextWindow
    let lastModified: Date
    var id: String { agentId }
}

struct ContextWindowState: Sendable {
    let main: ContextWindow
    let activeAgents: [AgentContext]
}
