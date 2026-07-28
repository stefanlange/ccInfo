import Foundation
import OSLog

/// Bridges raw JSONL model ID strings to family/version/pricing lookup
struct ModelIdentifier: Sendable, Hashable {
    let rawId: String
    let family: ClaudeModel
    let version: String?
    let pricingKey: String
    let isFallback: Bool

    private static let logger = Logger(subsystem: "com.ccinfo.app", category: "ModelIdentifier")

    var displayName: String {
        guard let version = version else {
            return family.displayName
        }
        return "\(family.displayName) \(version)"
    }

    init(rawId: String, availableModelKeys: Set<String>) {
        self.rawId = rawId
        self.family = Self.detectFamily(rawId)
        self.version = Self.extractVersion(rawId)

        let resolved = Self.resolvePricingKey(rawId, family: family, availableModelKeys: availableModelKeys)
        self.pricingKey = resolved.key
        self.isFallback = resolved.isFallback
    }

    static let unknown = ModelIdentifier(rawId: "<unknown>", availableModelKeys: [])

    // MARK: - Identity

    // Identity is the raw model ID alone. `pricingKey` and `isFallback` are derived from whichever
    // rate table happened to be loaded when this value was built, so including them would let one
    // model occupy two slots in a `Set` — once resolved via family fallback, once matched exactly.

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

    private static func newestModelForFamily(_ family: String, in keys: Set<String>) -> String {
        // Strip date stamps before the numeric compare, and do it once per key rather than inside
        // the comparator — this runs per JSONL entry whose model needs a fallback.
        let ranked = keys
            .filter { $0.contains(family.lowercased()) }
            .map { key in
                (key: key,
                 version: key.replacing(Self.dateStampRegex, with: "")
                    .matches(of: Self.digitRunRegex).compactMap { Int($0.output) },
                 isCanonical: !key.contains("/") && !key.contains("."))
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
