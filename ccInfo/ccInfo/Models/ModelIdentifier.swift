import Foundation
import OSLog

/// Bridges raw JSONL model ID strings to family/version/pricing lookup
struct ModelIdentifier: Sendable, Hashable {
    let rawId: String
    let family: ClaudeModel
    let version: String?
    let pricingKey: String
    let isFallback: Bool
    /// Context window the model ships with, `nil` when the rate table has nothing usable for it.
    let nativeMaxInputTokens: Int?
    /// The model charges above 200k input tokens, which marks its 1M window as opt-in.
    let hasLongContextPremium: Bool

    private static let logger = Logger(subsystem: "com.ccinfo.app", category: "ModelIdentifier")

    /// The model's 1M window is a paid beta mode, not the window it runs in by default.
    ///
    /// Two signals have to agree, because neither is sufficient on its own. An above-200k input
    /// rate says a long-context tier exists — but that is a pricing fact, and the table pairs it
    /// with natively 1M models too (`us.anthropic.claude-opus-4-6-v1` reports 1M *and* a premium).
    /// The version says which models actually gate 1M behind a beta header: Sonnet 4 and 4.5 do,
    /// Sonnet 4.6 onwards ships it. Testing the premium alone would clamp a future Sonnet to 200k
    /// the day Anthropic starts charging for its long context, which is the very bug this avoids.
    /// An unparsable version keeps the clamp, so dated and provider-scoped forms of those two
    /// models stay covered.
    var reachesExtendedContextOnlyViaBeta: Bool {
        guard family == .sonnet, hasLongContextPremium else { return false }
        guard let version = Self.numericVersion(version) else { return true }
        return version <= (major: 4, minor: 5)
    }

    var displayName: String {
        guard let version = version else {
            return family.displayName
        }
        return "\(family.displayName) \(version)"
    }

    init(rawId: String, catalog: PricingCatalog) {
        self.rawId = rawId
        self.family = Self.detectFamily(rawId)
        self.version = Self.extractVersion(rawId)

        let resolved = Self.resolvePricingKey(rawId, family: family, availableModelKeys: catalog.modelKeys)
        self.pricingKey = resolved.key
        self.isFallback = resolved.isFallback

        let context = Self.contextInfo(for: resolved, in: catalog)
        self.nativeMaxInputTokens = context?.maxInputTokens
        self.hasLongContextPremium = context?.hasLongContextPremium ?? false
    }

    static let unknown = ModelIdentifier(rawId: "<unknown>", catalog: .empty)

    // MARK: - Identity

    // Identity is the raw model ID alone. `pricingKey`, `isFallback`, `nativeMaxInputTokens` and
    // `hasLongContextPremium` are derived from whichever rate table happened to be loaded when
    // this value was built, so including them would let one model occupy two slots in a `Set` —
    // once resolved via family fallback, once matched exactly.

    static func == (lhs: ModelIdentifier, rhs: ModelIdentifier) -> Bool {
        lhs.rawId == rhs.rawId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(rawId)
    }

    // MARK: - Compiled Regexes
    // Hoisted to static constants so each pattern is compiled once, not on every call.
    // `extractVersion`/`newestModelForFamily` run per JSONL entry on the cost hot path.

    /// `claude-{family}-{major}-{minor}(-{date})?` — minor bounded to 1–2 digits so it can't
    /// swallow an 8-digit date suffix. Example: "claude-opus-4-6", "claude-sonnet-4-5-20250929".
    private static let majorMinorVersionRegex = /claude-[a-z]+-(\d+)-(\d{1,2})(?:-\d{8})?/
    /// `claude-{family}-{major}(-{date})?` — single version number. Example: "claude-fable-5".
    private static let majorOnlyVersionRegex = /claude-[a-z]+-(\d+)(?:-\d{8})?/
    /// Legacy `claude-{major}-{family}-{date}`. Example: "claude-3-opus-20240229".
    private static let legacyVersionRegex = /claude-(\d+)-[a-z]+-\d{8}/
    /// Runs of digits, for element-wise numeric comparison of model keys.
    private static let digitRunRegex = /\d+/
    /// Release date stamps: `-20250514` (Anthropic/Bedrock) and `@20250514` (Vertex AI). Neither
    /// is a version component — left in place, `[4, 20250514]` outranks `[4, 8]` and the family
    /// fallback picks a year-old model. Matching only `-` would leave the Vertex form behind.
    private static let dateStampRegex = /[-@]\d{8}/

    // MARK: - Private Detection Methods

    private static func detectFamily(_ id: String) -> ClaudeModel {
        let lower = id.lowercased()
        if lower.contains("fable") {
            return .fable
        } else if lower.contains("opus") {
            return .opus
        } else if lower.contains("sonnet") {
            return .sonnet
        } else if lower.contains("haiku") {
            return .haiku
        } else {
            return .unknown
        }
    }

    private static func extractVersion(_ id: String) -> String? {
        // New format: claude-{family}-{major}-{minor}(-{date})?
        if let match = id.wholeMatch(of: Self.majorMinorVersionRegex) {
            let major = String(match.1)
            let minor = String(match.2)
            return "\(major).\(minor)"
        }

        // Major-only format: claude-{family}-{major}(-{date})?
        if let match = id.wholeMatch(of: Self.majorOnlyVersionRegex) {
            return String(match.1)
        }

        // Legacy format: claude-{major}-{family}-{date}
        if let match = id.wholeMatch(of: Self.legacyVersionRegex) {
            return String(match.1)
        }

        // Short forms and unknown cases have no version
        return nil
    }

    private static func resolvePricingKey(_ id: String, family: ClaudeModel, availableModelKeys: Set<String>) -> (key: String, isFallback: Bool) {
        let lower = id.lowercased()

        // Step 1: Exact match
        if availableModelKeys.contains(lower) {
            return (lower, false)
        }

        // Step 2: Short form resolution (not a fallback - intentional)
        let shortForms = ["fable", "opus", "sonnet", "haiku"]
        if shortForms.contains(lower) {
            let newest = newestModelForFamily(lower, in: availableModelKeys)
            logger.debug("Short form '\(id)' resolved to '\(newest)'")
            return (newest, false)
        }

        // Step 3: Family fallback
        if family != .unknown {
            let newest = newestModelForFamily(family.rawValue, in: availableModelKeys)
            logger.debug("Model '\(id)' not found, family fallback to '\(newest)'")
            return (newest, true)
        }

        // Step 4: Sonnet default
        logger.debug("Model '\(id)' unknown, using Sonnet default")
        return ("claude-sonnet-4-5", true)
    }

    /// Window facts for a resolved key — but only when that key really describes this model.
    ///
    /// A family fallback lands on the newest key of the family. For a rate that is the best guess
    /// available; for a window it is a trap. The version-descending sort in `newestModelForFamily`
    /// only prefers canonical keys on a *tie*, so a provider-scoped key with a higher version
    /// number wins outright — and the table carries provider entries whose window contradicts
    /// their canonical sibling (`au.anthropic.claude-opus-4-6-v1:0` reports 200k where
    /// `claude-opus-4-6` reports 1M). Return nothing rather than import one of those; the caller
    /// then stays on its own conservative default. An exact match keeps its value: for a model
    /// only listed under a provider key, that entry is the best information there is.
    private static func contextInfo(
        for resolved: (key: String, isFallback: Bool),
        in catalog: PricingCatalog
    ) -> ModelContextInfo? {
        guard !resolved.isFallback || isCanonicalKey(resolved.key) else { return nil }
        return catalog.contextInfo[resolved.key]
    }

    /// A plain `claude-…` key, as opposed to a provider-scoped one (`us.anthropic.…`,
    /// `vertex_ai/…`, `claude-sonnet-4-5-20250929-v1:0`).
    ///
    /// The `:` matters as much as the other two: a Bedrock-shaped key carries no dot, so without it
    /// `…-v1:0` counts as canonical, wins a version tie on its longer version array, and hands its
    /// regional rate and possibly contradictory window to a family fallback.
    private static func isCanonicalKey(_ key: String) -> Bool {
        !key.contains("/") && !key.contains(".") && !key.contains(":")
    }

    /// `version` as comparable components — `"4"` → `(4, 0)`, `"4.5"` → `(4, 5)`.
    private static func numericVersion(_ version: String?) -> (major: Int, minor: Int)? {
        guard let version else { return nil }
        let parts = version.split(separator: ".")
        guard let major = parts.first.flatMap({ Int($0) }) else { return nil }
        guard parts.count > 1 else { return (major, 0) }
        guard let minor = Int(parts[1]) else { return nil }
        return (major, minor)
    }

    private static func newestModelForFamily(_ family: String, in keys: Set<String>) -> String {
        // Strip date stamps before the numeric compare, and do it once per key rather than inside
        // the comparator — this runs per JSONL entry whose model needs a fallback.
        let ranked = keys
            .filter { $0.contains(family.lowercased()) }
            .map { key in
                (key: key,
                 version: key.replacing(Self.dateStampRegex, with: "")
                    .matches(of: Self.digitRunRegex).compactMap { Int($0.output) },
                 isCanonical: isCanonicalKey(key))
            }
            .sorted { a, b in
                // Compare element-wise descending
                for (aNum, bNum) in zip(a.version, b.version) where aNum != bNum {
                    return aNum > bNum
                }

                // Same version: prefer the plain `claude-…` key over a provider-scoped one.
                // Bedrock and Vertex charge a regional premium, and their suffixes (`-v1:0`,
                // `@default`) also pad the version array, so without this they'd win on length.
                if a.isCanonical != b.isCanonical { return a.isCanonical }

                // If all compared elements equal, longer version array wins
                if a.version.count != b.version.count { return a.version.count > b.version.count }

                // Break remaining ties by name: `Set` iteration order is seeded per process, so
                // without this the chosen key — and the rate it carries — varies between launches.
                return a.key < b.key
            }

        return ranked.first?.key ?? "claude-sonnet-4-5"
    }
}
