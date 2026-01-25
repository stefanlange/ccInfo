import Foundation

struct JSONLEntry: Codable, Sendable {
    let type: String?
    let sessionId: String?
    let timestamp: Date?
    let message: Message?

    struct Message: Codable, Sendable {
        let role: String?
        let usage: TokenUsage?
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
}

struct SessionData: Sendable {
    let sessionId: String
    let tokens: TokenStats

    struct TokenStats: Sendable {
        // API pricing constants (Sonnet 4, per million tokens)
        private enum Pricing {
            static let inputPerMillion: Double = 3.0
            static let outputPerMillion: Double = 15.0
        }

        let input: Int
        let output: Int
        let cacheCreation: Int
        let cacheRead: Int

        var totalInput: Int { input + cacheCreation + cacheRead }

        var estimatedCost: Double {
            let inputCost = Double(totalInput) / 1_000_000 * Pricing.inputPerMillion
            let outputCost = Double(output) / 1_000_000 * Pricing.outputPerMillion
            return inputCost + outputCost
        }

        static var zero: TokenStats {
            TokenStats(input: 0, output: 0, cacheCreation: 0, cacheRead: 0)
        }

        static func + (lhs: TokenStats, rhs: TokenStats) -> TokenStats {
            TokenStats(
                input: lhs.input + rhs.input,
                output: lhs.output + rhs.output,
                cacheCreation: lhs.cacheCreation + rhs.cacheCreation,
                cacheRead: lhs.cacheRead + rhs.cacheRead
            )
        }
    }
}

struct ContextWindow: Sendable {
    // Context window constants
    private enum Constants {
        static let defaultMaxTokens = 200_000
        static let autoCompactThreshold = 45_000
    }

    let currentTokens: Int
    let maxTokens: Int

    var utilization: Double {
        maxTokens > 0 ? Double(currentTokens) / Double(maxTokens) * 100 : 0
    }

    var isNearAutoCompact: Bool {
        currentTokens >= maxTokens - Constants.autoCompactThreshold
    }

    init(currentTokens: Int, maxTokens: Int = Constants.defaultMaxTokens) {
        self.currentTokens = currentTokens
        self.maxTokens = maxTokens
    }
}
