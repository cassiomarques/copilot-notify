import Foundation

/// Navigates to a specific tmux pane and brings iTerm to front.
public struct TmuxNavigator {
    
    /// Navigate to the tmux pane for a given alert.
    /// If paneId is not pre-populated, attempts a live lookup.
    public static func navigate(to alert: SessionAlert) -> Bool {
        var paneId = alert.tmuxPaneId
        
        // If no pane mapping, try a live lookup now
        if paneId == nil {
            paneId = TmuxMapper.findPaneForSession(sessionId: alert.id)
        }
        
        guard let targetPane = paneId else {
            print("[CopilotNotify] No tmux pane found for session \(alert.id)")
            return false
        }
        
        // Select the tmux window and pane
        let result = shell("tmux select-window -t '\(targetPane)' 2>&1 && tmux select-pane -t '\(targetPane)' 2>&1")
        print("[CopilotNotify] tmux navigate to \(targetPane): \(result)")
        
        // Bring iTerm to front via AppleScript
        activateITerm()
        
        return true
    }
    
    /// Bring iTerm2 to the foreground.
    private static func activateITerm() {
        let script = "tell application \"iTerm2\" to activate"
        let _ = shell("osascript -e '\(script)'")
    }
    
    private static func shell(_ command: String) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines) ?? ""
        } catch {
            return "error: \(error)"
        }
    }
}
