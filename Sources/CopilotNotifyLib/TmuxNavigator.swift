import Foundation

/// Navigates to a specific tmux pane and brings iTerm to front.
public struct TmuxNavigator {
    
    /// Navigate to the tmux pane for a given alert.
    /// Sends `fg` first to resume any stopped process, then focuses the pane.
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
        
        // Send `fg` to resume any stopped process in that pane (harmless if nothing is stopped)
        let _ = shell("tmux send-keys -t '\(targetPane)' 'fg' Enter 2>/dev/null")
        
        // Select the tmux window and pane
        let result = shell("tmux select-window -t '\(targetPane)' 2>&1 && tmux select-pane -t '\(targetPane)' 2>&1")
        print("[CopilotNotify] tmux navigate to \(targetPane): \(result)")
        
        // Bring iTerm to front via AppleScript
        activateITerm()
        
        return true
    }
    
    /// Kill the copilot process for a session.
    public static func killSession(alert: SessionAlert) -> Bool {
        guard let pid = findPidForSession(alert: alert) else {
            print("[CopilotNotify] No PID found to kill for session \(alert.id)")
            return false
        }
        
        print("[CopilotNotify] Killing copilot process \(pid) for session \(alert.id)")
        // Kill the process group to also terminate child processes
        let result = shell("kill -TERM -\(pid) 2>/dev/null; kill -TERM \(pid) 2>/dev/null")
        print("[CopilotNotify] Kill result: \(result)")
        
        // Give it a moment, then force kill if still alive
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0) {
            let check = Self.shell("ps -p \(pid) -o pid= 2>/dev/null")
            if !check.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("[CopilotNotify] Process \(pid) still alive, sending SIGKILL")
                let _ = Self.shell("kill -9 \(pid) 2>/dev/null")
            }
        }
        
        return true
    }
    
    /// Find the PID of the copilot process for a given session.
    private static func findPidForSession(alert: SessionAlert) -> Int? {
        // Check via lsof for the session.db file
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let sessionDb = "\(home)/.copilot/session-state/\(alert.id)/session.db"
        let output = shell("lsof -t '\(sessionDb)' 2>/dev/null")
        
        // Return the first PID found
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let pid = Int(trimmed) {
                return pid
            }
        }
        return nil
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
