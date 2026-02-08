# Release Notes

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
