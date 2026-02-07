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

    // MARK: - Private Detection Methods

    private static func detectFamily(_ id: String) -> ClaudeModel {
        let lower = id.lowercased()
        if lower.contains("opus") {
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
        // Example: "claude-opus-4-6" or "claude-sonnet-4-5-20250929"
        if let match = id.wholeMatch(of: /claude-[a-z]+-(\d+)-(\d+)(?:-\d{8})?/) {
            let major = String(match.1)
            let minor = String(match.2)
            return "\(major).\(minor)"
        }

        // Legacy format: claude-{major}-{family}-{date}
        // Example: "claude-3-opus-20240229"
        if let match = id.wholeMatch(of: /claude-(\d+)-[a-z]+-\d{8}/) {
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
        let shortForms = ["opus", "sonnet", "haiku"]
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
        let familyModels = keys.filter { $0.contains(family.lowercased()) }

        let sorted = familyModels.sorted { a, b in
            // Extract all numeric components
            let aNumbers = a.matches(of: /\d+/).compactMap { Int($0.output) }
            let bNumbers = b.matches(of: /\d+/).compactMap { Int($0.output) }

            // Compare element-wise descending
            for (aNum, bNum) in zip(aNumbers, bNumbers) {
                if aNum != bNum {
                    return aNum > bNum
                }
            }

            // If all compared elements equal, longer version array wins
            return aNumbers.count > bNumbers.count
        }

        return sorted.first ?? "claude-sonnet-4-5"
    }
}
