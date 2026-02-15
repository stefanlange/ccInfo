import Foundation

// MARK: - LiteLLM Model (Raw JSON)

/// Represents a single model entry from LiteLLM's pricing JSON
struct LiteLLMModel: Codable, Sendable {
    let inputCostPerToken: Double
    let outputCostPerToken: Double
    let cacheCreationInputTokenCost: Double?
    let cacheReadInputTokenCost: Double?
    let maxOutputTokens: Int?
    let maxInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputCostPerToken = "input_cost_per_token"
        case outputCostPerToken = "output_cost_per_token"
        case cacheCreationInputTokenCost = "cache_creation_input_token_cost"
        case cacheReadInputTokenCost = "cache_read_input_token_cost"
        case maxOutputTokens = "max_output_tokens"
        case maxInputTokens = "max_input_tokens"
    }

    /// Models with 1M context window have special tiered pricing above 200k input tokens
    var isExtendedContext: Bool {
        (maxInputTokens ?? maxOutputTokens ?? 0) >= 500_000
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
    /// Note: This is standard context pricing (no tiering)
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

// MARK: - Cached Pricing Data

/// Container for cached pricing data with extended context metadata
struct CachedPricingData: Codable, Sendable {
    let pricing: [String: ModelPricing]
    let extendedContextKeys: Set<String>
    let cacheVersion: Int

    init(pricing: [String: ModelPricing], extendedContextKeys: Set<String>) {
        self.pricing = pricing
        self.extendedContextKeys = extendedContextKeys
        self.cacheVersion = 1
    }
}

// MARK: - Tiered Model Pricing

/// Wraps ModelPricing with tiered rates for 1M-context models
/// Models with 1M context windows (Opus 4.6, etc.) use higher input token rates above 200k tokens
struct TieredModelPricing: Sendable {
    let base: ModelPricing
    let inputTokenThreshold: Int?          // nil = no tiering
    let inputCostPerTokenAboveThreshold: Double?
    let cacheCreationCostPerTokenAboveThreshold: Double?
    let cacheReadCostPerTokenAboveThreshold: Double?

    /// Create tiered pricing from base pricing
    /// - Parameters:
    ///   - base: Base ModelPricing for below-threshold tokens
    ///   - isExtendedContext: true for 1M-context models (applies 1.25x rates above 200k tokens)
    static func from(base: ModelPricing, isExtendedContext: Bool) -> TieredModelPricing {
        if isExtendedContext {
            // 1M-context models: 200k threshold, 1.25x rates above
            // Output rate is NOT tiered (Anthropic only tiers input tokens)
            return TieredModelPricing(
                base: base,
                inputTokenThreshold: 200_000,
                inputCostPerTokenAboveThreshold: base.inputCostPerToken * 1.25,
                cacheCreationCostPerTokenAboveThreshold: base.cacheCreationCostPerToken * 1.25,
                cacheReadCostPerTokenAboveThreshold: base.cacheReadCostPerToken * 1.25
            )
        } else {
            // Standard context: no tiering
            return TieredModelPricing(
                base: base,
                inputTokenThreshold: nil,
                inputCostPerTokenAboveThreshold: nil,
                cacheCreationCostPerTokenAboveThreshold: nil,
                cacheReadCostPerTokenAboveThreshold: nil
            )
        }
    }

    /// Sonnet default with no tiering (standard context)
    static var sonnetDefault: TieredModelPricing {
        TieredModelPricing.from(base: ModelPricing.sonnetDefault, isExtendedContext: false)
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
