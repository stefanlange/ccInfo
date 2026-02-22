# Release Notes

## 1.6.2 – 2026-02-22

- Show a 0% context bar with "No active session" instead of hiding the section when no session is selected
- Replace segmented session picker with a dropdown showing full project names
- Stream JSONL files via FileHandle with defer-based cleanup and limit context window reads to the last 1 MB
- Lower autocompact warning threshold to 90% for 200K-context models
- Fix concurrency bugs in AuthWebView cookie callback, FileWatcher FSEvents bridge, and KeychainService
- Fill in missing German translations

## 1.6.1 – 2026-02-21

- Fix stale data appearing when switching periods or sessions quickly
- Show project path from JSONL working directory instead of guessing from folder names, with tooltip in session picker
- Keep showing the last active session after the activity threshold expires
- Show percentage instead of token count for subagent context windows
- Improve model badge contrast with solid backgrounds
- Fix SwiftUI accent color fallback by replacing .tint() with custom ProgressViewStyle
- Polish usage chart spacing, background, and glow indicator
- Drop sub-second precision from persisted usage timestamps

## 1.6.0 – 2026-02-17

- Replace 5-hour progress bar with interactive area chart showing usage timeline across the full window
- Color-code chart fill and line by usage zone with smooth interpolation (green → yellow → orange → red)
- Show glowing indicator at the current position within the 5-hour window relative to reset time
- Display Y-axis labels (0%, 50%, 100%) and X-axis labels (0h–5h) with dashed threshold lines
- Persist usage history to Application Support for continuity across app restarts
- Detect 5-hour window resets and clear history automatically
- Desaturate chart colors slightly in Dark Mode for comfortable viewing

## 1.5.0 – 2026-02-15

- Add configurable MenuBar display slots to choose which two metrics appear in the menu bar (5-hour, weekly, sonnet weekly, or context window)
- Add statistics period switcher with session, today, week, and month aggregation including loading spinner on period change
- Move context window section to the top of the dropdown for immediate visibility
- Unify bar color thresholds across all views to a consistent green/yellow/orange/red scale at 50/75/90%
- Show autocompact warning at 95% context utilization with percentage display matching usage sections
- Add VoiceOver accessibility labels and traits across all MenuBar components
- Separate MenuBar slot settings into dedicated section in Settings dialog
- Open Settings dialog on the active display and bring it above all windows
- Refactor JSONLParser with TokenAccumulator to reduce code duplication
- Fix PricingService cache round-trip to persist extended context keys
- Add `@MainActor` isolation and weak self in async closures for thread safety
- Complete German localization for all UI strings
- Replace print() with OSLog Logger in authentication flow
- Percent-encode organization ID in API URL construction

## 1.4.0 – 2026-02-14

- Align token and cost calculations with ccusage for consistent values across all time periods
- Use API-provided cost (costUSD) from JSONL entries as primary cost source instead of own calculation
- Count tokens from all JSONL entries, including those without a model ID
- Deduplicate entries across JSONL files using messageId and requestId to prevent double-counting
- Include subagent session tokens and costs in all views (Session, Today, Week, Month)
- Apply tiered pricing for 1M-context models (Opus 4.6, Sonnet 4.5+) with higher rates above 200k input tokens

## 1.3.0 – 2026-02-08

- Add multi-session switcher to toggle between active Claude Code sessions (configurable activity threshold in Settings)
- Show active subagent context windows with model badge and utilization bar
- Simplify update banner to single line with download icon
- Add macOS notification when a new app update is available
- Update privacy policy to reflect notification and pricing data usage
- Fix MainActor isolation for KeychainService init

## 1.2.0 – 2026-02-07

- Add dynamic pricing service that fetches live model prices from LiteLLM every 12 hours, with bundled JSON fallback
- Calculate session cost per JSONL entry using actual model pricing instead of fixed Sonnet 4 rates
- Show estimated cost with tilde prefix (~) when a model is not in the pricing database
- Add pricing data status row in Settings About tab showing data source and last update time
- Use fixed USD formatting with adaptive precision for cost display
- Add privacy policy
- Fix footer button label alignment
- Split CI and release into separate workflows

## 1.1.1 – 2026-02-06

- Use MARKETING_VERSION variable in Info.plist for version injection
- Fetch tags in separate step to avoid checkout conflict
- Fix version detection for branch pushes on tagged commits

## 1.1.0 – 2026-02-06

- Add configurable statistics period with today/week/month aggregation
- Calculate cost per JSONL entry using actual model pricing
- Add update checker with hourly auto-check
- Move JSONLParser off main thread by converting to actor
- Derive app version from git tag, show commit hash for dev builds
- Stack footer buttons vertically with larger font
- Add await for actor initializer to fix Xcode 15.4 build

## 1.0.3 – 2026-02-01

- Notifications and improved model display

## 1.0.2 – 2026-01-26

- Add app icon and improve UI
- Add Gatekeeper bypass instructions to README

## 1.0.1 – 2026-01-25

- Fix: restore executable permissions in DMG

## 1.0.0 – 2026-01-25

- Initial release
- macOS MenuBar app for monitoring Claude usage
- Real-time 5-hour and 7-day utilization display
- Session token statistics from local JSONL files
- Automated release workflow with DMG creation
