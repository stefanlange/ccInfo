# ccInfo

> Know your limits. Use them wisely.

A native macOS MenuBar app for real-time monitoring of your Claude usage.

![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## Features

### Usage Monitoring

- **5-Hour Window Tracking** – Current session utilization with color-coded area chart and reset countdown
- **Weekly Limit Monitoring** – 7-day quota with separate Sonnet and Opus breakdowns (real data from claude.ai)
- **Context Window Status** – Monitor your main context and active subagent context windows with model badge, utilization bar, and autocompact warning
- **Configurable MenuBar Slots** – Choose which two metrics to display in the MenuBar (5-hour, weekly, sonnet weekly, or context window)

### Session Intelligence

- **Multi-Session Switcher** – Switch between active Claude Code sessions via dropdown menu (with configurable activity threshold)
- **Token Statistics** – Input/output token counts aggregated by session, today, week, or month
- **Dynamic Cost Estimation** – Live model pricing via LiteLLM with per-model cost calculation
- **Burn Rate Calculation** – Understand your token consumption velocity

### Auto-Updates & Configuration

- **Update Checker** – Automatic hourly checks with macOS notification when a new version is available
- **Configurable Refresh Interval** – Manual or automatic polling from 30 seconds to 10 minutes
- **Launch at Login** – Start ccInfo automatically with macOS
- **Secure Authentication** – Session tokens stored in macOS Keychain
- **VoiceOver Accessible** – Full VoiceOver support across all MenuBar components

## Installation

### Download

1. Download the latest release from [Releases](https://github.com/stefanlange/ccInfo/releases)
2. Open the DMG and drag the app to `/Applications`
3. **First launch:** The app is not notarized by Apple. On first launch:
   - **Right-click** (or Ctrl+click) on CCInfo.app → **Open** → click **Open** in the dialog
   - *Or* go to **System Settings** → **Privacy & Security** → scroll down and click **Open Anyway**
   - *Or* run `xattr -cr /Applications/CCInfo.app` in Terminal
4. Launch and sign in with your Claude account

### Build from Source

```bash
git clone https://github.com/stefanlange/ccInfo.git
cd ccInfo
open CCInfo/CCInfo.xcodeproj
```

Build with ⌘B, run with ⌘R.

## Requirements

- macOS 14.0 (Sonoma) or later
- Active Claude Pro or Max subscription

## Privacy

- Stores tokens locally in the macOS Keychain
- Communicates only with claude.ai and the LiteLLM pricing API
- Collects no telemetry
- Sends no data to third parties

See [PRIVACY.md](PRIVACY.md) for details.

## Release Notes

See [RELEASENOTES.md](RELEASENOTES.md) for the full changelog.

## License

MIT License – see [LICENSE](LICENSE) for details.

---

*Not affiliated with Anthropic. Claude is a trademark of Anthropic, PBC.*
