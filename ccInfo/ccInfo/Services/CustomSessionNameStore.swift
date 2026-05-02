import Foundation
import Observation
import OSLog

/// Persistent store for user-defined custom session names, keyed by `projectDirectory` slug.
///
/// - Persistence: JSON-encoded `[String: String]` written to `UserDefaults` under
///   `AppStorageKeys.customSessionNamesV1` (`"session.customNames.v1"`).
/// - Reset semantics: empty or whitespace-only names are treated as a clear (D-09).
/// - Slug keys are case-sensitive (D-10) — no normalization is performed.
/// - Names are clamped to `maxNameLength` characters at write time.
/// - Decode failures fall back to an empty dictionary + warning log (D-07/D-08).
/// - Mutations are atomic: encode runs before in-memory mutation, so memory and disk
///   never disagree on a successful write. On encode failure neither side changes.
/// - Test seam: `init(defaults:)` allows injecting an isolated `UserDefaults` instance (D-12).
@Observable
@MainActor
final class CustomSessionNameStore {
    /// Maximum character count for a single custom name. Names longer than this
    /// are clamped (paste guard). 200 chars covers any plausible project label
    /// while keeping `Picker` rendering and JSON re-encode cost bounded.
    static let maxNameLength = 200

    /// In-memory snapshot of all persisted entries (slug → custom name).
    /// Read-only from the outside; `set`/`clear` are the supported mutations.
    private(set) var entries: [String: String] = [:]

    private let defaults: UserDefaults
    private let key = AppStorageKeys.customSessionNamesV1
    private let encoder = JSONEncoder()
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
    /// Names are clamped to `maxNameLength` characters before storage.
    /// Atomic: on encode failure neither memory nor disk are mutated.
    func setCustomName(_ name: String, for slug: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clearCustomName(for: slug)
            return
        }
        let clamped = String(trimmed.prefix(Self.maxNameLength))
        var next = entries
        next[slug] = clamped
        commit(next)
    }

    /// Removes the custom name for `slug`. A subsequent `customName(for:)` returns `nil`.
    /// Atomic: on encode failure neither memory nor disk are mutated.
    func clearCustomName(for slug: String) {
        guard entries[slug] != nil else { return }
        var next = entries
        next.removeValue(forKey: slug)
        commit(next)
    }

    /// Removes every entry whose slug is not in `activeSlugs`. Returns the number of
    /// entries removed. Pure no-op if no orphans exist.
    @discardableResult
    func pruneOrphans(activeSlugs: Set<String>) -> Int {
        let next = entries.filter { activeSlugs.contains($0.key) }
        let removed = entries.count - next.count
        guard removed > 0 else { return 0 }
        commit(next)
        return removed
    }

    /// Forces `UserDefaults` to flush its in-memory cache to disk. AppKit's
    /// `applicationWillTerminate` runs synchronously, so a fire-and-forget `set(_:forKey:)`
    /// call right before quit can be torn down before the daemon flushes. Call this from
    /// the termination path to close that window.
    func flush() {
        defaults.synchronize()
    }

    // MARK: - Persistence

    /// Atomic write: encode `next` first, mutate `entries` only on success.
    /// On encode failure the in-memory state stays consistent with disk.
    private func commit(_ next: [String: String]) {
        if next.isEmpty {
            defaults.removeObject(forKey: key)
            entries = next
            return
        }
        do {
            let data = try encoder.encode(next)
            defaults.set(data, forKey: key)
            entries = next
        } catch {
            // D-07/D-08: log and abort the mutation. Memory still mirrors disk.
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
            // Reap the corrupt blob so the next launch starts from a clean state.
            logger.warning("Failed to decode \(key, privacy: .public) — starting with empty map: \(error.localizedDescription)")
            defaults.removeObject(forKey: key)
            return [:]
        }
    }
}
