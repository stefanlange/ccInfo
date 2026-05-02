import Foundation
import Observation
import OSLog

/// Persistent store for user-defined custom session names, keyed by `projectDirectory` slug.
///
/// - Persistence: JSON-encoded `[String: String]` written to `UserDefaults` under
///   `AppStorageKeys.customSessionNamesV1` (`"session.customNames.v1"`).
/// - Reset semantics: empty or whitespace-only names are treated as a clear.
/// - Slug keys are case-sensitive — no normalization is performed.
/// - Names are sanitized (control chars, bidi overrides, zero-width formatting stripped)
///   and clamped to `maxNameLength` characters at write time.
/// - Decode failures fall back to an empty dictionary + warning log; the corrupt blob
///   is reaped so the next launch starts clean.
/// - Mutations are atomic: encode runs before in-memory mutation, so memory and disk
///   never disagree on a successful write. On encode failure neither side changes.
/// - Test seam: `init(defaults:)` allows injecting an isolated `UserDefaults` instance.
@Observable
@MainActor
final class CustomSessionNameStore {
    /// Maximum character count for a single custom name. Names longer than this
    /// are clamped (paste guard). 200 chars covers any plausible project label
    /// while keeping `Picker` rendering and JSON re-encode cost bounded.
    static let maxNameLength = 200

    /// Characters stripped from any submitted custom name. Targets two attack surfaces
    /// plus three layout-corruption surfaces:
    /// - Bidi overrides (CVE-2021-42574 "Trojan Source" class) — `safe\u{202E}lufless`
    ///   would render as `sselfunsafe`, allowing visual spoofing in screenshots /
    ///   settings exports.
    /// - Zero-width formatting chars — make a name look empty while bypassing the
    ///   trim-and-clear empty-check.
    /// - C0/C1 control chars + DEL — break `Picker` row layout (newline) or render as
    ///   garbage glyphs.
    /// - Line / paragraph separators (U+2028 / U+2029).
    /// `U+200D` ZWJ is preserved because it's required for emoji ligatures such as 👨‍👩‍👧.
    private static let disallowedSet: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: Unicode.Scalar(0x00)!..<Unicode.Scalar(0x20)!)
        set.insert(Unicode.Scalar(0x7F)!)
        set.insert(charactersIn: Unicode.Scalar(0x80)!..<Unicode.Scalar(0xA0)!)
        set.insert(charactersIn: "\u{200E}\u{200F}\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}")
        set.insert(charactersIn: "\u{200B}\u{200C}\u{FEFF}")
        set.insert(charactersIn: "\u{2028}\u{2029}")
        return set
    }()

    private static func sanitize(_ name: String) -> String {
        name.components(separatedBy: disallowedSet).joined()
    }

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
    /// Slug lookup is case-sensitive.
    func customName(for slug: String) -> String? {
        entries[slug]
    }

    /// Sets the custom name for `slug`. Empty or whitespace-only `name` is treated as a
    /// clear. Sanitization (strip control / bidi / zero-width chars) runs first,
    /// then trim, then clamp to `maxNameLength`. Atomic: on encode failure neither
    /// memory nor disk are mutated.
    func setCustomName(_ name: String, for slug: String) {
        let sanitized = Self.sanitize(name)
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
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
            // Log and abort the mutation so memory still mirrors disk.
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
            // Corrupt or foreign-schema raw value → empty map + warning.
            // Reap the corrupt blob so the next launch starts from a clean state.
            logger.warning("Failed to decode \(key, privacy: .public) — starting with empty map: \(error.localizedDescription)")
            defaults.removeObject(forKey: key)
            return [:]
        }
    }
}
