# Release Notes

## 1.13.0 – 2026-06-07

- Redesign the 5-hour usage chart: taller, with a smoothed curve, a fill that fades from the line toward the baseline, and a soft glow on the current value
- Blend the chart color gradually from green to yellow as usage rises, instead of holding flat green and then shifting abruptly near the top
- Translate the Reload and error buttons into German (they previously showed English), and reword the reset countdown, weekly-limit, and token-limit messages for more natural German

## 1.12.0 – 2026-05-02

- Rename any session via the pencil button next to the switcher or the new Sessions tab in Settings; names persist across restarts and replace the auto-derived project name everywhere
- Show the absolute reset time of the 5-hour window below the chart (e.g. "Mo 1.5. 16:30") next to the existing time-until-reset countdown

## 1.11.1 – 2026-04-26

- Trigger sign-in automatically when Anthropic invalidates the session, so the menu bar no longer gets stuck on a stale error
- Update menu bar usage and the dropdown together right after sign-in, instead of needing a restart
- Show the login form again after sign-out, instead of the chat from the previous session
- Open the auth window reliably from any trigger, even with the app in the background, and add a manual reload button for rare blank-window cases
- Stop reopening the auth window in a loop when the same session keeps being rejected
- Bump Sparkle to 2.9.1

## 1.11.0 – 2026-04-19

- Align the tilde and cost amount in the session row so they share the same baseline instead of the tilde floating half a step above
- Anchor the about-tab divider to the 64pt app-icon width so it reads as an underline rather than a full-pane section break
- Keep the pricing status timestamp in the About tab refreshing every minute while the window is open, so "N minutes ago" no longer goes stale
- Swap the refresh button's arrow icon for a small spinner while a refresh is running, with a 250 ms minimum-display window to avoid flicker on cached refreshes
- Show a two-line tooltip on inactive sessions with the configured activity threshold in minutes; active sessions keep their single-line path tooltip
- Localize notification titles and bodies so German builds no longer leak English "5-Hour"/"weekly" labels — the window name is now resolved through the string catalog
- Add German translations for "Not signed in", "No data", the new Loading label, and the inactive-session tooltip
- Fix burn chart data loss when the app is terminated unexpectedly by saving history more often and on app termination
- Refactor the codebase onto implicit LocalizedStringKey so future strings pick up their translations automatically
- Centralize typography and spacing in shared Swift enums (ShareableChartView keeps its export-only typography)
- Save usage history off the main thread so the app no longer pauses briefly on each poll
- Clear the usage chart at the 5-hour window reset instead of drawing a vertical cliff from the retired window down to 0%
- Stop the pricing status timestamp timer when the About tab is hidden so it doesn't keep ticking in the background
- Stop VoiceOver from reading "Tap to retry" twice when the error banner is focused

## 1.10.0 – 2026-04-12

- Show a burn rate warning when the current token consumption pace will exhaust the 5-hour window before it resets, with a flame icon in the menu bar, a red inline banner in the popover, and a one-shot macOS notification
- Fix the session dropdown occasionally showing the encoded project path instead of the project name

## 1.9.0 – 2026-03-31

- Redesign Settings as a sidebar navigation with colored icon badges and the app icon on the About tab
- Replace the flat green chart fill with a smooth horizontal color gradient that follows the usage level from green through yellow to orange
- Fix a visual gap in the usage chart after restarting the app
- Fix chart gaps reappearing on the next launch by stripping restart markers from saved history
- Fix high CPU usage during active Claude sessions by switching FSEvents to directory-level coalescing and adding caches for parsed paths, context windows, and JSONL byte offsets
- Parse JSONL files incrementally — only new bytes are read after the initial parse, cutting steady-state I/O to near zero
- Combine the two directory walks for session discovery into a single pass
- Migrate AppState from ObservableObject to @Observable for fine-grained SwiftUI re-renders
- Implement Sparkle gentle reminders so update dialogs appear correctly for background apps

## 1.8.3 – 2026-03-25

- Compact the three footer buttons (Refresh, Settings, Quit) to icons with hover tooltips
- Switch CI and release builds to the macOS 26 SDK for Liquid Glass on Tahoe

## 1.8.2 – 2026-03-21

- Add a Sonnet context window setting (200K/1M) in Settings for plans without extended context
- Store credentials as a local file instead of macOS Keychain, fixing the password prompt after every app update
- Migrate existing Keychain credentials on first launch and delete the old entry
- Hide sessions whose project directory no longer exists (e.g. after removing a git worktree)
- Rename the project from CCInfo to ccInfo to match the repo and DMG naming

## 1.8.1 – 2026-03-15

- Recognize the new 1M context window for Sonnet and Opus instead of relying on a token-count heuristic (Haiku stays at 200k)
- Use a flat 33k autocompact buffer for all context sizes and warn at 20k tokens remaining instead of a fixed percentage
- Sign Sparkle's nested XPC services individually to fix auto-update install failures on ad-hoc signed builds
- Defer Sparkle startup to after app launch so it no longer blocks the menu bar icon from appearing
- Reset usage notification thresholds on sign-out to avoid missed alerts after re-authentication
- Stop subagent context windows from swapping positions in the list while multiple agents are active
- Fail the release workflow early when the signing key is missing or release notes are empty

## 1.8.0 – 2026-03-15

- Replace the manual update checker with Sparkle for automatic in-app updates, including EdDSA signature verification
- Add an Updates tab in Settings with a toggle for automatic checks (every 4 hours, enabled by default) and a manual check button
- Sign releases with EdDSA and publish a Sparkle appcast to GitHub Pages as part of the release pipeline
- Fix ad-hoc codesigning to preserve Sparkle XPC service entitlements (drop `--deep`, apply `disable-library-validation`)
- Remove the old UpdateChecker, update banner, and update notification in favor of Sparkle's native update dialog
- Add German translations for the new update settings

## 1.7.1 – 2026-03-01

- Add copy-to-clipboard option in the chart share sheet (missing in ad-hoc signed builds)

## 1.7.0 – 2026-03-01

- Share the 5-hour usage chart as a dark-themed PNG via the macOS share sheet, with thumbnail preview in the picker
- Show readable session names for Claude-internal projects instead of encoded directory paths
- Move chart drawing into a shared helper so the live chart and export use the same code

## 1.6.3 – 2026-02-28

- Fix empty session picker when the active session file is replaced by a newer one
- Fix phantom green line in burn chart when usage is zero
- Preserve statistics when switching sessions for Today, Week, and Month periods
- Stop auto-switching to other sessions when the current one goes inactive
- Clean up duplicated logic and scattered defaults

## 1.6.2 – 2026-02-22

- Show a 0% context bar with "No active session" instead of hiding the section when no session is selected
- Replace segmented session picker with a dropdown showing full project names
- Stream JSONL files via FileHandle with defer-based cleanup and limit context window reads to the last 1 MB
- Lower autocompact warning threshold to 90% for 200K-context models
- Fix concurrency bugs in AuthWebView cookie callback, FileWatcher FSEvents bridge, and KeychainService
- Fill in missing German translations
- Fix crash on first menu bar click when color lookup table is not yet initialized

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
