import Foundation
import Observation

/// Coordinates session-rename drafts and persistence across both edit surfaces
/// (MenuBar Quick-Edit popover and Settings → Sessions tab).
///
/// Owns the draft state lifted out of view-local `@State` so drafts survive
/// view tear-down (e.g. Settings window closing, app termination). Both
/// surfaces call `commit(_:for:)`, `discard(slug:)`, and `reset(slug:)` —
/// trim + clear-on-empty live in one place (`CustomSessionNameStore`), so
/// the surfaces cannot disagree on what counts as "save".
///
/// Lifecycle: `flush()` from `applicationWillTerminate` commits any open drafts
/// before the process tears down — closes the Cmd-Q race window where a typed
/// name would otherwise be lost.
@Observable
@MainActor
final class SessionRenameModel {
    private let store: CustomSessionNameStore
    private(set) var drafts: [String: String] = [:]

    init(store: CustomSessionNameStore) {
        self.store = store
    }

    // MARK: - Read

    /// Returns the live draft for `slug` if one exists, otherwise the persisted
    /// custom name (or empty string if none). Use this to seed a TextField's
    /// initial value on first read.
    func draft(for slug: String) -> String {
        if let existing = drafts[slug] { return existing }
        return store.customName(for: slug) ?? ""
    }

    /// Whether a draft exists for `slug` (i.e. the user typed something that
    /// has not yet been committed). Useful for skip-save guards on focus loss.
    func hasDraft(for slug: String) -> Bool {
        drafts[slug] != nil
    }

    // MARK: - Mutate draft

    /// Stores the in-flight draft for `slug` without persisting. Call from
    /// TextField bindings on every keystroke.
    func setDraft(_ value: String, for slug: String) {
        drafts[slug] = value
    }

    // MARK: - Commit

    /// Persists `value` as the custom name for `slug` and clears any draft.
    /// Trim + empty-string-as-reset are handled by the store. Use this when
    /// the surface owns its draft locally (e.g. popover with single-string state).
    func commit(_ value: String, for slug: String) {
        store.setCustomName(value, for: slug)
        drafts.removeValue(forKey: slug)
    }

    /// Persists the current draft (if any) for `slug`. No-op when no draft exists.
    /// Use from focus-loss / submit handlers when the draft lives in `drafts`.
    func commitDraft(for slug: String) {
        guard let draft = drafts[slug] else { return }
        commit(draft, for: slug)
    }

    /// Drops the draft for `slug` without persisting. Use on Cancel / dismiss.
    func discard(slug: String) {
        drafts.removeValue(forKey: slug)
    }

    /// Clears any persisted custom name for `slug` and drops the draft.
    func reset(slug: String) {
        store.clearCustomName(for: slug)
        drafts.removeValue(forKey: slug)
    }

    // MARK: - Termination

    /// Commits every open draft and forces `UserDefaults` to flush. Safe to call
    /// from `applicationWillTerminate` — runs synchronously on the main actor.
    func flush() {
        for slug in drafts.keys {
            store.setCustomName(drafts[slug] ?? "", for: slug)
        }
        drafts.removeAll()
        store.flush()
    }
}
