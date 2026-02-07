# Release Notes

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
