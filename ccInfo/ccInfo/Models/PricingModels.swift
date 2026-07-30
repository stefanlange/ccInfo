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
///
/// `Equatable` so a refresh can tell a genuinely new rate table from a reload of the same one.
/// Exact `Double` comparison is right here: these values come straight out of the JSON decode
/// and no arithmetic touches them before storage.
struct ModelPricing: Codable, Sendable, Equatable {
    let inputCostPerToken: Double
    let outputCostPerToken: Double
    let cacheCreationCostPerToken: Double
    let cacheReadCostPerToken: Double
    /// Long-context tier rates (above 200k input tokens). `nil` = flat pricing, no premium.
    let inputCostPerTokenAbove200k: Double?
    let cacheCreationCostPerTokenAbove200k: Double?
    let cacheReadCostPerTokenAbove200k: Double?
    /// Raw `max_input_tokens` as published. Feeds the context window via `ModelContextInfo`,
    /// which is where the value gets sanity-checked — stored unfiltered so the check lives
    /// in one place.
    let maxInputTokens: Int?

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
        self.maxInputTokens = litellm.maxInputTokens
    }

    /// Direct initialization for default/fallback values
    init(inputCostPerToken: Double, outputCostPerToken: Double, cacheCreationCostPerToken: Double, cacheReadCostPerToken: Double,
         inputCostPerTokenAbove200k: Double? = nil, cacheCreationCostPerTokenAbove200k: Double? = nil, cacheReadCostPerTokenAbove200k: Double? = nil,
         maxInputTokens: Int? = nil) {
        self.inputCostPerToken = inputCostPerToken
        self.outputCostPerToken = outputCostPerToken
        self.cacheCreationCostPerToken = cacheCreationCostPerToken
        self.cacheReadCostPerToken = cacheReadCostPerToken
        self.inputCostPerTokenAbove200k = inputCostPerTokenAbove200k
        self.cacheCreationCostPerTokenAbove200k = cacheCreationCostPerTokenAbove200k
        self.cacheReadCostPerTokenAbove200k = cacheReadCostPerTokenAbove200k
        self.maxInputTokens = maxInputTokens
    }
}

// MARK: - Model Context Info

/// Context-window facts for one model, distilled from its rate-table entry.
///
/// Two fields of the rate data say different things, and only together do they describe the
/// window a session actually runs in: `max_input_tokens` is the size the model can reach, while
/// an above-200k input rate marks a 1M window that has to be switched on — and paid extra for —
/// rather than one the model simply has. LiteLLM does not keep those apart: `claude-sonnet-4-5`
/// reports 200k, but `claude-sonnet-4-20250514` reports 1M even though both only reach 1M behind
/// a beta header. The tier rate is present on exactly those two and absent on every natively
/// 1M model (sonnet-5, sonnet-4-6, opus-5/4-8/4-7/4-6, fable-5), so it is the reliable signal.
struct ModelContextInfo: Sendable, Equatable {
    /// Window sizes Anthropic ships. Raw values are snapped onto these.
    static let standardWindow = 200_000
    static let extendedWindow = 1_000_000

    let maxInputTokens: Int
    /// The model charges a premium above 200k input tokens — its 1M window is opt-in.
    let hasLongContextPremium: Bool

    /// Fails when the entry carries no usable window size, leaving the consumer on its own default.
    init?(pricing: ModelPricing) {
        guard let window = Self.snapToShippedWindow(pricing.maxInputTokens) else { return nil }
        self.maxInputTokens = window
        self.hasLongContextPremium = pricing.inputCostPerTokenAbove200k != nil
    }

    /// Snap a published `max_input_tokens` onto a shipped window size, rounding **down**.
    ///
    /// The table carries values that are neither size (409600 on `gmi/…`, 128000 and 80000 on
    /// `github_copilot/…`, 100000 on the Claude 2 era) as well as nulls. Rounding down means a
    /// value between the two sizes warns about auto-compact too early rather than too late.
    ///
    /// Below 200k there is nothing to round down to, so those entries and the nulls return nothing
    /// and the consumer falls back to 200k — larger than the real window, which errs the other way.
    /// It stays theoretical for this app: every such key is a Claude 2 or non-Anthropic model whose
    /// ID carries no family word, so `ContextWindow` never sees a model for it in the first place.
    private static func snapToShippedWindow(_ raw: Int?) -> Int? {
        guard let raw else { return nil }
        if raw >= extendedWindow { return extendedWindow }
        if raw >= standardWindow { return standardWindow }
        return nil
    }
}

// MARK: - Pricing Catalog

/// Everything a parse pass needs to look up from the rate table, taken as one value.
///
/// The parts are derived from the same table, so they have to travel together: resolving a model
/// against one generation's keys and then reading a window size out of another's would mix two
/// tables in a single `ModelIdentifier`. Carrying the generation inside makes that a property of
/// the type rather than a rule callers have to remember — anything cached from a catalog can be
/// checked against the generation the cache is tagged with.
struct PricingCatalog: Sendable {
    /// The `PricingService.generation` this catalog was derived from.
    let generation: Int
    /// Lowercased keys of every model in the table.
    let modelKeys: Set<String>
    /// Context-window facts by lowercased key. Models whose entry carries no usable window
    /// size are absent rather than guessed at.
    let contextInfo: [String: ModelContextInfo]

    /// Generation `-1` so an empty catalog never matches a real one — nothing resolved through it
    /// may be filed under a live generation.
    static let empty = PricingCatalog(generation: -1, modelKeys: [], contextInfo: [:])
}

// MARK: - Cached Pricing Data

/// Container for cached pricing data, tagged with a schema version for cache migration.
struct CachedPricingData: Codable, Sendable {
    let pricing: [String: ModelPricing]
    let cacheVersion: Int

    /// Bumped to 2 when tiered pricing moved from a hardcoded 1.25x heuristic to the
    /// real above-200k rates carried in `ModelPricing`. Older caches lack those fields
    /// and self-heal on the next refresh.
    ///
    /// Bumped to 3 when `maxInputTokens` joined `ModelPricing` to drive the context window.
    /// A v2 entry decodes with that field nil, which would put every 1M model back on the
    /// 200k default until the next successful fetch — up to 12 hours of wrong utilization.
    static let currentVersion = 3

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
