import Foundation

/// Maps copilot sessions to their tmux panes.
public struct TmuxMapper {
    
    struct PaneInfo {
        let paneId: String      // e.g. "%33"
        let target: String      // e.g. "1:3.2" (session:window.pane)
        let tty: String         // e.g. "/dev/ttys020"
    }
    
    struct CopilotProcess {
        let pid: Int
        let tty: String         // e.g. "ttys020"
        let cwd: String?
        let sessionId: String?  // from --session-id flag if present
    }
    
    /// Get all tmux panes with their tty mappings.
    static func listPanes() -> [PaneInfo] {
        let output = shell("tmux list-panes -a -F '#{pane_tty} #{session_name}:#{window_index}.#{pane_index} #{pane_id}'")
        var panes: [PaneInfo] = []
        
        for line in output.components(separatedBy: .newlines) {
            let parts = line.components(separatedBy: " ")
            guard parts.count >= 3 else { continue }
            panes.append(PaneInfo(paneId: parts[2], target: parts[1], tty: parts[0]))
        }
        return panes
    }
    
    /// Find all running copilot CLI processes.
    /// Matches the main copilot process (not child workers/bootstrap processes).
    static func findCopilotProcesses() -> [CopilotProcess] {
        // Match processes whose command is exactly "copilot" or ends with "/copilot" 
        // (optionally followed by flags like --resume, --session-id, etc.)
        // Exclude bootstrap/extension workers.
        let output = shell("ps -eo pid,tty,command | grep -E '(^|/)copilot( |$)' | grep -v grep | grep -v extension_bootstrap | grep -v node")
        var processes: [CopilotProcess] = []
        
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: " ", maxSplits: 2)
            guard parts.count >= 2,
                  let pid = Int(parts[0]) else { continue }
            let tty = String(parts[1])
            
            // Skip processes with no tty (background/detached)
            guard tty != "??" else { continue }
            
            // Extract session-id from command args if present
            var sessionId: String? = nil
            if parts.count >= 3 {
                let cmd = String(parts[2])
                if let range = cmd.range(of: "--session-id ") {
                    let afterFlag = cmd[range.upperBound...]
                    sessionId = String(afterFlag.prefix(while: { !$0.isWhitespace }))
                }
            }
            
            // If no --session-id flag, try to find session from open session.db file
            if sessionId == nil {
                sessionId = getMostRecentSessionFromOpenFiles(pid: pid)
            }
            
            // Get cwd via lsof
            let cwd = getCwd(pid: pid)
            processes.append(CopilotProcess(pid: pid, tty: tty, cwd: cwd, sessionId: sessionId))
        }
        return processes
    }
    
    /// Map sessions to tmux panes by matching session ID or cwd.
    public static func mapAlerts(_ alerts: inout [String: SessionAlert]) {
        let panes = listPanes()
        let processes = findCopilotProcesses()
        
        // Build tty -> pane lookup
        var ttyToPanes: [String: PaneInfo] = [:]
        for pane in panes {
            let shortTty = pane.tty.replacingOccurrences(of: "/dev/", with: "")
            ttyToPanes[shortTty] = pane
        }
        
        // For each copilot process, find its pane and match to a session
        for process in processes {
            guard let pane = ttyToPanes[process.tty] else { continue }
            
            // Strategy 1: Match by --session-id flag (most reliable)
            if let procSessionId = process.sessionId, alerts[procSessionId] != nil {
                alerts[procSessionId]?.tmuxTarget = pane.target
                alerts[procSessionId]?.tmuxPaneId = pane.paneId
                alerts[procSessionId]?.tty = process.tty
                continue
            }
            
            // Strategy 2: Match by cwd from workspace.yaml
            if let cwd = process.cwd {
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                for (sessionId, alert) in alerts where alert.tmuxPaneId == nil {
                    let workspacePath = "\(home)/.copilot/session-state/\(sessionId)/workspace.yaml"
                    if let workspace = WorkspaceInfo.parse(from: workspacePath),
                       let sessionCwd = workspace.cwd,
                       sessionCwd == cwd {
                        alerts[sessionId]?.tmuxTarget = pane.target
                        alerts[sessionId]?.tmuxPaneId = pane.paneId
                        alerts[sessionId]?.tty = process.tty
                        break
                    }
                }
            }
        }
    }
    
    /// Find the tmux pane for a specific session (synchronous, for on-demand lookup).
    public static func findPaneForSession(sessionId: String) -> String? {
        let panes = listPanes()
        let processes = findCopilotProcesses()
        
        var ttyToPanes: [String: PaneInfo] = [:]
        for pane in panes {
            let shortTty = pane.tty.replacingOccurrences(of: "/dev/", with: "")
            ttyToPanes[shortTty] = pane
        }
        
        // Strategy 1: Match by --session-id flag
        for process in processes {
            if process.sessionId == sessionId, let pane = ttyToPanes[process.tty] {
                return pane.paneId
            }
        }
        
        // Strategy 2: Match by cwd
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let workspacePath = "\(home)/.copilot/session-state/\(sessionId)/workspace.yaml"
        guard let workspace = WorkspaceInfo.parse(from: workspacePath),
              let sessionCwd = workspace.cwd else { return nil }
        
        for process in processes {
            guard let cwd = process.cwd, cwd == sessionCwd,
                  let pane = ttyToPanes[process.tty] else { continue }
            return pane.paneId
        }
        
        return nil
    }
    
    /// Find session IDs that have active copilot processes.
    /// Matches by --session-id flag or by cwd against workspace.yaml.
    public static func findActiveSessionIds(sessionStatePath: String) -> Set<String> {
        let processes = findCopilotProcesses()
        var activeIds = Set<String>()
        
        // Direct matches via --session-id flag
        for process in processes {
            if let sid = process.sessionId {
                activeIds.insert(sid)
            }
        }
        
        // Match remaining by cwd (fallback for processes where lsof didn't find session.db)
        let fm = FileManager.default
        guard let sessionDirs = try? fm.contentsOfDirectory(atPath: sessionStatePath) else {
            return activeIds
        }
        
        for process in processes where process.sessionId == nil {
            guard let cwd = process.cwd else { continue }
            for dirName in sessionDirs {
                guard !activeIds.contains(dirName) else { continue }
                let workspacePath = "\(sessionStatePath)/\(dirName)/workspace.yaml"
                if let workspace = WorkspaceInfo.parse(from: workspacePath),
                   let sessionCwd = workspace.cwd,
                   sessionCwd == cwd {
                    activeIds.insert(dirName)
                    break
                }
            }
        }
        
        return activeIds
    }
    
    /// Get the current working directory of a process.
    private static func getCwd(pid: Int) -> String? {
        let output = shell("lsof -a -p \(pid) -d cwd -Fn 2>/dev/null | grep '^n/'")
        // lsof output: "n/path/to/dir"
        for line in output.components(separatedBy: .newlines) {
            if line.hasPrefix("n/") {
                return String(line.dropFirst(1))
            }
        }
        return nil
    }
    
    /// Extract session ID from open session.db files.
    /// If multiple session.db files are open, picks the most recently modified one.
    private static func getMostRecentSessionFromOpenFiles(pid: Int) -> String? {
        let output = shell("lsof -a -p \(pid) -Fn 2>/dev/null | grep 'session-state/.*/session.db'")
        var candidates: [String] = []
        
        for line in output.components(separatedBy: .newlines) {
            guard line.contains("session-state/") else { continue }
            let cleaned = line.hasPrefix("n") ? String(line.dropFirst(1)) : line
            if let stateRange = cleaned.range(of: "session-state/"),
               let dbRange = cleaned.range(of: "/session.db") {
                let sessionId = String(cleaned[stateRange.upperBound..<dbRange.lowerBound])
                if !sessionId.isEmpty {
                    candidates.append(sessionId)
                }
            }
        }
        
        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return candidates[0] }
        
        // Multiple sessions — pick the one with the most recently modified events.jsonl
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fm = FileManager.default
        var best: String? = nil
        var bestDate = Date.distantPast
        
        for sessionId in candidates {
            let eventsPath = "\(home)/.copilot/session-state/\(sessionId)/events.jsonl"
            if let attrs = try? fm.attributesOfItem(atPath: eventsPath),
               let modDate = attrs[.modificationDate] as? Date,
               modDate > bestDate {
                bestDate = modDate
                best = sessionId
            }
        }
        
        return best ?? candidates[0]
    }
    
    /// Extract session ID from open session.db files (returns first match — used by findPaneForSession).
    private static func getSessionIdFromOpenFiles(pid: Int) -> String? {
        let output = shell("lsof -a -p \(pid) -Fn 2>/dev/null | grep 'session-state/.*/session.db'")
        for line in output.components(separatedBy: .newlines) {
            guard line.contains("session-state/") else { continue }
            let cleaned = line.hasPrefix("n") ? String(line.dropFirst(1)) : line
            if let stateRange = cleaned.range(of: "session-state/"),
               let dbRange = cleaned.range(of: "/session.db") {
                let sessionId = String(cleaned[stateRange.upperBound..<dbRange.lowerBound])
                if !sessionId.isEmpty {
                    return sessionId
                }
            }
        }
        return nil
    }
    
    /// Run a shell command and return stdout.
    private static func shell(_ command: String) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines) ?? ""
        } catch {
            return ""
        }
    }
}
