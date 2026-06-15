# Copilot Notify

A macOS menu bar app that notifies you when your [GitHub Copilot CLI](https://githubnext.com/projects/copilot-cli) sessions need attention.

## Features

- **Menu bar icon** with badge count showing sessions needing attention
- **System notifications** when a session completes, asks a question, or needs plan approval
- **Click-to-navigate** — clicking a session jumps to the correct tmux pane and brings iTerm2 to front
- **Auto-dismiss** — alerts disappear automatically when you respond to a session
- **Lightweight** — pure Swift, no runtime dependencies, polls every 3 seconds

## Alert Types

| Type | Trigger | Icon |
|------|---------|------|
| Completion | Task completed | ✅ |
| Question | Agent asked a question / waiting for input | ❓ |
| Approval | Plan needs review/approval | 📋 |
| Working | Agent is actively processing | 🔄 |

## Installation

### From GitHub Releases (recommended)

1. Download the latest `CopilotNotify.dmg` or `CopilotNotify.zip` from [Releases](https://github.com/cassiomarques/copilot-notify/releases)
2. Move `CopilotNotify.app` to `/Applications` or `~/Applications`
3. Open it — the bell icon appears in your menu bar

### From source

```bash
# Clone and build
git clone https://github.com/cassiomarques/copilot-notify.git
cd copilot-notify

# Build and install to ~/Applications
make install

# Or just build the .app bundle
make app
open dist/CopilotNotify.app
```

## Requirements

- macOS 13.0+
- Swift 6.1+ (for building from source)
- tmux (for pane navigation)
- iTerm2 (for window activation)
- GitHub Copilot CLI

## Usage

```bash
# Quick debug build (no system notifications)
swift build && .build/debug/CopilotNotify

# Release build with app bundle (enables system notifications)
make app
open dist/CopilotNotify.app

# Build and install to ~/Applications
make install
```

## Launch at Login

```bash
# Install the LaunchAgent
cp Resources/com.cassiomarques.CopilotNotify.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.cassiomarques.CopilotNotify.plist

# To unload
launchctl unload ~/Library/LaunchAgents/com.cassiomarques.CopilotNotify.plist
```

Note: The LaunchAgent expects the app at `/Applications/CopilotNotify.app`. Adjust the path in the plist if you install elsewhere.

## Creating a Release

Tag a version to trigger the release workflow:

```bash
git tag v0.1.0
git push origin v0.1.0
```

This will build the app, create a DMG and ZIP, and publish them as a GitHub Release.

## How It Works

1. **Polling**: Every 3 seconds, scans `~/.copilot/session-state/` for active sessions
2. **Event parsing**: Reads each session's `events.jsonl` to determine state (completion, question, working, etc.)
3. **Process detection**: Uses `lsof` to find which session each copilot process belongs to (via open `session.db` files)
4. **tmux mapping**: Correlates copilot process PIDs → tty → tmux pane via `ps` and `tmux list-panes`
5. **Navigation**: Uses `tmux select-pane` + AppleScript to jump to the correct pane and activate iTerm2

## Architecture

```
Sources/
├── CopilotNotifyApp/
│   └── App.swift               # Entry point, wires components together
└── CopilotNotifyLib/
    ├── SessionAlert.swift      # Data model
    ├── SessionMonitor.swift    # Polls session-state directory
    ├── EventParser.swift       # Parses events.jsonl files
    ├── WorkspaceInfo.swift     # Parses workspace.yaml metadata
    ├── TmuxMapper.swift        # Maps sessions to tmux panes
    ├── TmuxNavigator.swift     # Navigates to pane + activates iTerm
    ├── NotificationManager.swift # macOS system notifications
    ├── StatusBarController.swift # NSStatusItem + popover
    └── SessionListView.swift   # SwiftUI list UI
```

## Running Tests

```bash
swift test
# or
make test
```
