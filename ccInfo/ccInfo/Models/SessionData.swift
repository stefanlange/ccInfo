import Foundation

// MARK: - Statistics Period

enum StatisticsPeriod: String, CaseIterable, Sendable {
    case session, today, thisWeek, thisMonth

    var displayName: String {
        switch self {
        case .session:   return String(localized: "Session")
        case .today:     return String(localized: "Today")
        case .thisWeek:  return String(localized: "Week")
        case .thisMonth: return String(localized: "Month")
        }
    }

    /// First letter of displayName for compact segments
    var shortLabel: String {
        String(displayName.prefix(1))
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
    case fable = "fable"
    case opus = "opus"
    case sonnet = "sonnet"
    case haiku = "haiku"
    case unknown = "unknown"

    var displayName: String {
        switch self {
        case .fable: return "Fable"
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
    let costUSD: Double?
    let requestId: String?

    struct Message: Codable, Sendable {
        let role: String?
        let usage: TokenUsage?
        let model: String?
        let id: String?
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

    /// Extract message ID from nested message structure
    var messageId: String? {
        message?.id
    }

    /// Unique hash for deduplication (messageId:requestId)
    var uniqueHash: String? {
        guard let mid = messageId, let rid = requestId else { return nil }
        return "\(mid):\(rid)"
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
    private enum Constants {
        static let standardMaxTokens = ModelContextInfo.standardWindow
        static let extendedMaxTokens = ModelContextInfo.extendedWindow
        static let autoCompactBuffer = 33_000
        static let autoCompactWarningBuffer = 20_000
    }

    let currentTokens: Int
    let activeModel: ModelIdentifier?
    /// Window the model is expected to run in, taken from the rate table.
    let nativeMaxTokens: Int

    /// Never assume a window smaller than the session has demonstrably filled.
    ///
    /// A 200k session cannot hold more than 200k tokens, so a transcript that shows more proves a
    /// larger window was active. That is the only signal available for Sonnet models whose 1M
    /// window sits behind a beta header: the transcript records no trace of the header, and the
    /// rate table reports the same size either way. It also catches a table that lags behind a
    /// model's real window, and it costs nothing when the expectation was right.
    ///
    /// Two limits worth knowing. The jump goes straight to 1M because those are the only two sizes
    /// Anthropic ships; a third size would need a real ladder here. And the proof is the *current*
    /// token count, so it is not sticky: once Claude Code compacts a beta-window session back under
    /// 200k, the smaller window is assumed again until it grows past the mark. Keeping a per-session
    /// high-water mark would fix that, but it would only hold for as long as the app stays running.
    var maxTokens: Int {
        currentTokens > nativeMaxTokens ? Constants.extendedMaxTokens : nativeMaxTokens
    }

    init(currentTokens: Int, activeModel: ModelIdentifier? = nil) {
        self.currentTokens = currentTokens
        self.activeModel = activeModel

        guard let activeModel else {
            self.nativeMaxTokens = Constants.standardMaxTokens
            return
        }
        // For a beta-gated 1M window, 200k is what the model runs in by default — whatever the
        // table reports as its ceiling. LiteLLM does not draw that line: `claude-sonnet-4-5` is
        // listed at 200k while `claude-sonnet-4-20250514` is listed at 1M, though both need the
        // header. Expect the smaller window for both and let `maxTokens` recover the larger one
        // from what the session actually used.
        self.nativeMaxTokens = activeModel.reachesExtendedContextOnlyViaBeta
            ? Constants.standardMaxTokens
            : activeModel.nativeMaxInputTokens ?? Constants.standardMaxTokens
    }

    var effectiveMaxTokens: Int {
        maxTokens - Constants.autoCompactBuffer
    }

    var utilization: Double {
        let maxValue = Swift.max(1, effectiveMaxTokens)
        let currentValue = Swift.max(0, currentTokens)
        return Swift.min(Double(currentValue) / Double(maxValue) * 100, 100)
    }

    var isNearAutoCompact: Bool {
        currentTokens >= effectiveMaxTokens - Constants.autoCompactWarningBuffer
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

// MARK: - Active Session

struct ActiveSession: Sendable, Identifiable, Hashable {
    let sessionURL: URL
    let projectDirectory: String
    let projectName: String
    let projectPath: String?
    let lastModified: Date
    let isActive: Bool

    var id: URL { sessionURL }

    func hash(into hasher: inout Hasher) {
        hasher.combine(sessionURL)
    }

    static func == (lhs: ActiveSession, rhs: ActiveSession) -> Bool {
        lhs.sessionURL == rhs.sessionURL
    }
}
