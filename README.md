# ccInfo

> Know your limits. Use them wisely.

A native macOS MenuBar app for real-time monitoring of your Claude usage.

![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## Features

- **5-Hour Window Tracking** – See your current session utilization with reset countdown
- **Weekly Limit Monitoring** – Track your 7-day quota (real data from Claude.ai)
- **Context Window Status** – Monitor how full your current context is
- **Burn Rate Calculation** – Understand your token consumption velocity
- **Cost Equivalent** – See what your usage would cost on API pricing
- **Secure Authentication** – Tokens stored in macOS Keychain

## Installation

### Download

1. Download the latest release from [Releases](https://github.com/stefanlange/ccInfo/releases)
2. Open the DMG and drag the app to `/Applications`
3. **Important:** The app is not notarized. macOS will show a warning on first launch. To open:
   ```bash
   xattr -cr /Applications/CCInfo.app
   ```
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

- ✅ Stores tokens locally in the macOS Keychain
- ✅ Communicates only with claude.ai
- ❌ Collects no telemetry
- ❌ Sends no data to third parties

See [PRIVACY.md](docs/PRIVACY.md) for details.

## License

MIT License – see [LICENSE](LICENSE) for details.

---

*Not affiliated with Anthropic. Claude is a trademark of Anthropic, PBC.*
