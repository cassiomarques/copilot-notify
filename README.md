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
| Completion | `session.task_complete` event | ✅ |
| Question | Agent asked a question / waiting for input | ❓ |
| Approval | Plan needs review/approval | 📋 |

## Requirements

- macOS 13.0+
- Swift 6.1+ (Xcode 16+)
- tmux (for pane navigation)
- iTerm2 (for window activation)
- GitHub Copilot CLI

## Build & Run

```bash
# Quick debug build (no system notifications)
swift build && .build/debug/CopilotNotify

# Release build with app bundle (enables system notifications)
./build.sh
open .build/release/CopilotNotify.app

# Build and install to ~/Applications
./build.sh --install
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

## How It Works

1. **Polling**: Every 3 seconds, scans `~/.copilot/session-state/` for sessions modified in the last 24 hours
2. **Event parsing**: Reads each session's `events.jsonl` to determine state (last event type, whether user has responded)
3. **tmux mapping**: Correlates copilot process PIDs → tty → tmux pane via `ps` and `tmux list-panes`
4. **Navigation**: Uses `tmux select-pane` + AppleScript to jump to the correct pane and activate iTerm2

## Architecture

```
Sources/
├── App.swift               # Entry point, wires components together
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
