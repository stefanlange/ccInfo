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
    // Explicit long-context tier rates (above 200k input tokens). Present only on models
    // that actually charge a long-context premium (e.g. Opus 4.6). Absent on flat-priced
    // 1M-window models (e.g. Fable), which must not be tiered.
    let inputCostPerTokenAbove200k: Double?
    let cacheCreationInputTokenCostAbove200k: Double?
    let cacheReadInputTokenCostAbove200k: Double?

    enum CodingKeys: String, CodingKey {
        case inputCostPerToken = "input_cost_per_token"
        case outputCostPerToken = "output_cost_per_token"
        case cacheCreationInputTokenCost = "cache_creation_input_token_cost"
        case cacheReadInputTokenCost = "cache_read_input_token_cost"
        case maxOutputTokens = "max_output_tokens"
        case maxInputTokens = "max_input_tokens"
        case inputCostPerTokenAbove200k = "input_cost_per_token_above_200k_tokens"
        case cacheCreationInputTokenCostAbove200k = "cache_creation_input_token_cost_above_200k_tokens"
        case cacheReadInputTokenCostAbove200k = "cache_read_input_token_cost_above_200k_tokens"
    }
}

// MARK: - Model Pricing (Internal)

/// Internal representation of model pricing with per-token costs
struct ModelPricing: Codable, Sendable {
    let inputCostPerToken: Double
    let outputCostPerToken: Double
    let cacheCreationCostPerToken: Double
    let cacheReadCostPerToken: Double
    /// Long-context tier rates (above 200k input tokens). `nil` = flat pricing, no premium.
    let inputCostPerTokenAbove200k: Double?
    let cacheCreationCostPerTokenAbove200k: Double?
    let cacheReadCostPerTokenAbove200k: Double?

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
        self.inputCostPerTokenAbove200k = litellm.inputCostPerTokenAbove200k
        self.cacheCreationCostPerTokenAbove200k = litellm.cacheCreationInputTokenCostAbove200k
        self.cacheReadCostPerTokenAbove200k = litellm.cacheReadInputTokenCostAbove200k
    }

    /// Direct initialization for default/fallback values
    init(inputCostPerToken: Double, outputCostPerToken: Double, cacheCreationCostPerToken: Double, cacheReadCostPerToken: Double,
         inputCostPerTokenAbove200k: Double? = nil, cacheCreationCostPerTokenAbove200k: Double? = nil, cacheReadCostPerTokenAbove200k: Double? = nil) {
        self.inputCostPerToken = inputCostPerToken
        self.outputCostPerToken = outputCostPerToken
        self.cacheCreationCostPerToken = cacheCreationCostPerToken
        self.cacheReadCostPerToken = cacheReadCostPerToken
        self.inputCostPerTokenAbove200k = inputCostPerTokenAbove200k
        self.cacheCreationCostPerTokenAbove200k = cacheCreationCostPerTokenAbove200k
        self.cacheReadCostPerTokenAbove200k = cacheReadCostPerTokenAbove200k
    }
}

// MARK: - Cached Pricing Data

/// Container for cached pricing data, tagged with a schema version for cache migration.
struct CachedPricingData: Codable, Sendable {
    let pricing: [String: ModelPricing]
    let cacheVersion: Int

    /// Bumped to 2 when tiered pricing moved from a hardcoded 1.25x heuristic to the
    /// real above-200k rates carried in `ModelPricing`. Older caches lack those fields
    /// and self-heal on the next refresh.
    static let currentVersion = 2

    init(pricing: [String: ModelPricing]) {
        self.pricing = pricing
        self.cacheVersion = Self.currentVersion
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

    /// Create tiered pricing from base pricing.
    ///
    /// Tiering is driven entirely by the model's own data: a model is tiered iff it carries
    /// an explicit above-200k input rate. Models with a 1M window but no published premium
    /// (e.g. Fable) stay flat — no fabricated surcharge. Output is never tiered (Anthropic
    /// only tiers input/cache tokens). Cache rates above the threshold fall back to the base
    /// rate if the data omits a tiered value while still tiering input.
    static func from(base: ModelPricing) -> TieredModelPricing {
        guard let aboveInput = base.inputCostPerTokenAbove200k else {
            return TieredModelPricing(
                base: base,
                inputTokenThreshold: nil,
                inputCostPerTokenAboveThreshold: nil,
                cacheCreationCostPerTokenAboveThreshold: nil,
                cacheReadCostPerTokenAboveThreshold: nil
            )
        }
        return TieredModelPricing(
            base: base,
            inputTokenThreshold: 200_000,
            inputCostPerTokenAboveThreshold: aboveInput,
            cacheCreationCostPerTokenAboveThreshold: base.cacheCreationCostPerTokenAbove200k ?? base.cacheCreationCostPerToken,
            cacheReadCostPerTokenAboveThreshold: base.cacheReadCostPerTokenAbove200k ?? base.cacheReadCostPerToken
        )
    }

    /// Sonnet default with no tiering (standard context)
    static var sonnetDefault: TieredModelPricing {
        TieredModelPricing.from(base: ModelPricing.sonnetDefault)
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
    case networkError(String)
    case parseError(String)
    case noBundledData

    var errorDescription: String? {
        switch self {
        case .httpError(let code):
            return String(localized: "HTTP error: \(code)")
        case .networkError(let message):
            return String(localized: "Network error: \(message)")
        case .parseError(let message):
            return String(localized: "Parse error: \(message)")
        case .noBundledData:
            return String(localized: "No bundled pricing data available")
        }
    }
}
