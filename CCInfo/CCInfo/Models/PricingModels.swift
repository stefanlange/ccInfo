import Foundation

// MARK: - LiteLLM Model (Raw JSON)

/// Represents a single model entry from LiteLLM's pricing JSON
struct LiteLLMModel: Codable, Sendable {
    let inputCostPerToken: Double
    let outputCostPerToken: Double
    let cacheCreationInputTokenCost: Double?
    let cacheReadInputTokenCost: Double?
    let maxOutputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputCostPerToken = "input_cost_per_token"
        case outputCostPerToken = "output_cost_per_token"
        case cacheCreationInputTokenCost = "cache_creation_input_token_cost"
        case cacheReadInputTokenCost = "cache_read_input_token_cost"
        case maxOutputTokens = "max_output_tokens"
    }
}

// MARK: - Model Pricing (Internal)

/// Internal representation of model pricing with per-token costs
struct ModelPricing: Codable, Sendable {
    let inputCostPerToken: Double
    let outputCostPerToken: Double
    let cacheCreationCostPerToken: Double
    let cacheReadCostPerToken: Double

    /// Conservative Sonnet 4 fallback pricing (per-token, not per-MTok)
    /// Input: $3/MTok = 3e-06, Output: $15/MTok = 1.5e-05
    /// Cache write: $3.75/MTok = 3.75e-06, Cache read: $0.30/MTok = 3e-07
    static var sonnetDefault: ModelPricing {
        ModelPricing(
            inputCostPerToken: 3e-06,
            outputCostPerToken: 1.5e-05,
            cacheCreationCostPerToken: 3.75e-06,
            cacheReadCostPerToken: 3e-07
        )
    }

    /// Initialize from LiteLLM model data
    init(from litellm: LiteLLMModel) {
        self.inputCostPerToken = litellm.inputCostPerToken
        self.outputCostPerToken = litellm.outputCostPerToken
        self.cacheCreationCostPerToken = litellm.cacheCreationInputTokenCost ?? 0.0
        self.cacheReadCostPerToken = litellm.cacheReadInputTokenCost ?? 0.0
    }

    /// Direct initialization for default/fallback values
    init(inputCostPerToken: Double, outputCostPerToken: Double, cacheCreationCostPerToken: Double, cacheReadCostPerToken: Double) {
        self.inputCostPerToken = inputCostPerToken
        self.outputCostPerToken = outputCostPerToken
        self.cacheCreationCostPerToken = cacheCreationCostPerToken
        self.cacheReadCostPerToken = cacheReadCostPerToken
    }
}

// MARK: - Pricing Data Source

/// Tracks the origin of currently loaded pricing data
enum PricingDataSource: Sendable {
    case live      // Fetched from network
    case cached    // Loaded from Application Support cache
    case bundled   // Loaded from app bundle fallback
}

// MARK: - Pricing Errors

enum PricingError: Error, LocalizedError {
    case httpError(Int)
    case networkError(Error)
    case parseError(Error)
    case noBundledData

    var errorDescription: String? {
        switch self {
        case .httpError(let code):
            return String(localized: "HTTP error: \(code)")
        case .networkError(let error):
            return String(localized: "Network error: \(error.localizedDescription)")
        case .parseError(let error):
            return String(localized: "Parse error: \(error.localizedDescription)")
        case .noBundledData:
            return String(localized: "No bundled pricing data available")
        }
    }
}
