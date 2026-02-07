# Privacy Policy

**ccInfo** is a native macOS MenuBar app. It is designed to respect your privacy. This document describes what data the app accesses, stores, and transmits.

## Data Stored Locally

| Data | Storage | Purpose |
|------|---------|---------|
| Session key, organization ID | macOS Keychain | API authentication |
| Statistics period, refresh interval | UserDefaults | User preferences |
| Model pricing cache | Application Support | Offline pricing fallback (refreshed every 12h) |

Keychain entries use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — they are only accessible when your Mac is unlocked and are excluded from iCloud backup.

## Network Connections

The app connects to exactly three external domains:

| Domain | Purpose |
|--------|---------|
| `claude.ai` | Fetching your usage data (5-hour and 7-day windows, organization name) |
| `api.github.com` | Checking for app updates (reads the latest release tag) |
| `raw.githubusercontent.com` | Fetching model pricing data from the LiteLLM open-source repository |

No authentication tokens, device identifiers, or personal data are sent to GitHub. The update check and pricing fetch are simple anonymous GET requests.

## Local File Access

The app reads Claude Code session files at `~/.claude/projects/**/*.jsonl` to calculate token statistics and context window usage. These files are read locally and never uploaded anywhere.

## What ccInfo Does NOT Do

- No analytics or telemetry
- No crash reporting
- No device fingerprinting or tracking IDs
- No data shared with third parties
- No clipboard, camera, microphone, or location access
- No iCloud sync

## App Permissions

The app requests no special entitlements. It uses:

- **Network access** for API calls to claude.ai, update checks via GitHub, and pricing data from LiteLLM
- **Keychain access** for secure credential storage
- **File system read access** to `~/.claude/projects/` for session data
- **Notification permission** (optional) for usage threshold alerts at 80% and 95%

## Open Source

ccInfo is fully open source. You can audit the complete source code at [github.com/stefanlange/ccInfo](https://github.com/stefanlange/ccInfo).
