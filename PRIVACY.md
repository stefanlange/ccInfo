# Privacy Policy

**ccInfo** is a native macOS MenuBar app. It is designed to respect your privacy. This document describes what data the app accesses, stores, and transmits.

## Data Stored Locally

| Data | Storage | Purpose |
|------|---------|---------|
| Session key, organization ID | Application Support (`credentials.json`, chmod 600) | API authentication |
| User preferences (refresh interval, statistics period, MenuBar slots, session activity threshold) | UserDefaults | App configuration |
| Model pricing cache | Application Support | Offline pricing fallback (refreshed every 12h) |
| Usage history (5-hour timeline) | Application Support | Area chart visualization of recent usage |

Credentials are stored as a JSON file with owner-only read/write permissions (chmod 600) in `~/Library/Application Support/ccInfo/`. They are not synced to iCloud.

## Network Connections

The app connects to exactly three external domains:

| Domain | Purpose |
|--------|---------|
| `claude.ai` | Fetching your usage data (5-hour and 7-day windows, organization name) |
| `stefanlange.github.io` | Checking for app updates via Sparkle appcast feed |
| `raw.githubusercontent.com` | Fetching model pricing data from the LiteLLM open-source repository |

No authentication tokens, device identifiers, or personal data are sent to GitHub. The update check fetches a static XML file (appcast) and the pricing fetch is a simple anonymous GET request.

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

The app uses one entitlement:

- **`disable-library-validation`** – Required for Sparkle's auto-update XPC services to load under ad-hoc code signing

It also uses:

- **Network access** for API calls to claude.ai, update checks via Sparkle appcast, and pricing data from LiteLLM
- **File system write access** to `~/Library/Application Support/ccInfo/` for credential and cache storage
- **File system read access** to `~/.claude/projects/` for session data
- **Notification permission** (optional) for usage threshold alerts (80%/95%)

## Open Source

ccInfo is fully open source. You can audit the complete source code at [github.com/stefanlange/ccInfo](https://github.com/stefanlange/ccInfo).
