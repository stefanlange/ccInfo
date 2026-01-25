# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Open in Xcode
open CCInfo/CCInfo.xcodeproj

# Build from command line (no code signing)
xcodebuild -project CCInfo/CCInfo.xcodeproj \
           -scheme CCInfo \
           -configuration Release \
           CODE_SIGNING_ALLOWED=NO
```

Build with ⌘B, run with ⌘R in Xcode.

## Project Overview

ccInfo is a native macOS MenuBar app for monitoring Claude usage. It displays real-time 5-hour and 7-day utilization percentages, context window status, and session token statistics.

**Requirements:** macOS 14.0+, Swift 5.9

## Architecture

### Data Flow

```
ClaudeAPIClient (actor) ──────┐
                              ├──▶ AppState (@MainActor) ──▶ SwiftUI Views
JSONLParser + FileWatcher ────┘
```

**AppState** (`App/AppDelegate.swift`) is the central coordinator:
- Owns all services and published state
- Polls usage API every 30 seconds
- Watches `~/.claude/projects/` for local session changes via FSEvents

### Data Sources

1. **Remote (claude.ai API):** 5-hour and 7-day usage windows from `/api/organizations/{id}/usage`
2. **Local (JSONL files):** Session tokens and context window from Claude Code's `~/.claude/projects/**/*.jsonl` files

### Key Components

| File | Purpose |
|------|---------|
| `Services/ClaudeAPIClient.swift` | Actor-based API client with session auth |
| `Services/JSONLParser.swift` | Parses Claude Code session files for token stats |
| `Services/FileWatcher.swift` | FSEvents wrapper for monitoring file changes |
| `Services/KeychainService.swift` | Secure credential storage |
| `Models/UsageData.swift` | API response models and domain types |
| `Models/SessionData.swift` | JSONL entry parsing and token calculations |

### Authentication

Credentials (sessionKey + organizationId) are extracted via WebView login and stored in macOS Keychain. On 401 response, credentials are cleared and re-auth is triggered.

### Token Cost Estimation

Session cost is calculated using Sonnet 4 API pricing: $3/MTok input, $15/MTok output (see `SessionData.TokenStats.estimatedCost`).
