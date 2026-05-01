import Foundation
import Observation
import OSLog

/// Persistent store for user-defined custom session names, keyed by `projectDirectory` slug.
///
/// - Persistence: JSON-encoded `[String: String]` written to `UserDefaults` under
///   `AppStorageKeys.customSessionNamesV1` (`"session.customNames.v1"`).
/// - Reset semantics: empty or whitespace-only names are treated as a clear (D-09).
/// - Slug keys are case-sensitive (D-10) — no normalization is performed.
/// - Decode failures fall back to an empty dictionary + warning log (D-07/D-08).
/// - Test seam: `init(defaults:)` allows injecting an isolated `UserDefaults` instance (D-12).
@Observable
@MainActor
final class CustomSessionNameStore {
    /// In-memory snapshot of all persisted entries (slug → custom name).
    /// Read-only from the outside; `set`/`clear` are the supported mutations.
    private(set) var entries: [String: String] = [:]

    private let defaults: UserDefaults
    private let key = AppStorageKeys.customSessionNamesV1
    private let logger = Logger(subsystem: "com.ccinfo.app", category: "CustomSessionNameStore")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.entries = Self.loadEntries(from: defaults, key: key, logger: logger)
    }

    // MARK: - Public API

    /// Returns the persisted custom name for the given slug, or `nil` if none is set.
    /// Slug lookup is case-sensitive (D-10).
    func customName(for slug: String) -> String? {
        entries[slug]
    }

    /// Sets the custom name for `slug`. Empty or whitespace-only `name` is treated as a
    /// clear (D-09). The trim is applied inside the store; callers don't have to prepare.
    /// Synchronous: in-memory mutation + UserDefaults write happen in the same call (D-06).
    func setCustomName(_ name: String, for slug: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clearCustomName(for: slug)
            return
        }
        entries[slug] = trimmed
        persist()
    }

    /// Removes the custom name for `slug`. A subsequent `customName(for:)` returns `nil`.
    /// Synchronous: in-memory mutation + UserDefaults write happen in the same call (D-06).
    func clearCustomName(for slug: String) {
        guard entries.removeValue(forKey: slug) != nil else { return }
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        do {
            if entries.isEmpty {
                defaults.removeObject(forKey: key)
            } else {
                let data = try JSONEncoder().encode(entries)
                defaults.set(data, forKey: key)
            }
        } catch {
            // D-07/D-08: log and keep going. In-memory state remains the source of truth
            // until the next successful encode.
            logger.error("Failed to encode custom session names: \(error.localizedDescription)")
        }
    }

    private static func loadEntries(
        from defaults: UserDefaults,
        key: String,
        logger: Logger
    ) -> [String: String] {
        guard let data = defaults.data(forKey: key) else {
            return [:]
        }
        do {
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            // D-07: corrupt or foreign-schema raw value → empty map + warning.
            // The next set() will overwrite the raw value (D-08: no backup, no skip-writes).
            logger.warning("Failed to decode \(key, privacy: .public) — starting with empty map: \(error.localizedDescription)")
            return [:]
        }
    }
}
