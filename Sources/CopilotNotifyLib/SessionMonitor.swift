import Foundation

/// Monitors all copilot sessions and detects which ones need attention.
public class SessionMonitor {
    private let sessionStatePath: String
    private var lastModTimes: [String: Date] = [:]  // session_id -> last known mod time
    public private(set) var alerts: [String: SessionAlert] = [:]  // session_id -> alert/state
    
    /// Callback fired when alerts change.
    public var onAlertsChanged: (([SessionAlert]) -> Void)?
    
    private var timer: Timer?
    private let pollInterval: TimeInterval
    
    /// Set of session IDs with running copilot processes (updated by tmux mapping).
    private var activeSessions: Set<String> = []
    
    /// Sessions hidden by the user (won't reappear until process exits and restarts).
    private var hiddenSessions: Set<String> = []
    
    public init(pollInterval: TimeInterval = 3.0, sessionStatePath: String? = nil) {
        if let path = sessionStatePath {
            self.sessionStatePath = path
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            self.sessionStatePath = "\(home)/.copilot/session-state"
        }
        self.pollInterval = pollInterval
    }
    
    public func start() {
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.scan()
        }
    }
    
    public func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    /// Dismiss/hide a session from the list. It won't reappear until its process exits and restarts.
    public func dismiss(sessionId: String) {
        hiddenSessions.insert(sessionId)
        if alerts.removeValue(forKey: sessionId) != nil {
            onAlertsChanged?(Array(alerts.values))
        }
    }
    
    /// Update tmux pane mappings and active session list.
    /// Runs on a background queue to avoid run-loop re-entrancy from Process.waitUntilExit().
    public func updateTmuxMappings() {
        let currentAlerts = alerts
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var copy = currentAlerts
            TmuxMapper.mapAlerts(&copy)
            
            // Determine which sessions have active copilot processes
            let activeSessionIds = TmuxMapper.findActiveSessionIds(sessionStatePath: self?.sessionStatePath ?? "")
            
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Un-hide sessions whose processes have exited
                let exitedHidden = self.hiddenSessions.subtracting(activeSessionIds)
                self.hiddenSessions.subtract(exitedHidden)
                
                self.activeSessions = activeSessionIds
                // Merge mappings back
                for (id, mapped) in copy {
                    if self.alerts[id] != nil {
                        self.alerts[id]?.tmuxTarget = mapped.tmuxTarget
                        self.alerts[id]?.tmuxPaneId = mapped.tmuxPaneId
                        self.alerts[id]?.tty = mapped.tty
                    }
                }
                // Re-scan to pick up newly discovered active sessions
                self.scan()
            }
        }
    }
    
    /// Main scan loop: check all session directories for state changes.
    public func scan() {
        let fm = FileManager.default
        guard let sessionDirs = try? fm.contentsOfDirectory(atPath: sessionStatePath) else { return }
        
        var changed = false
        let recentCutoff = Date().addingTimeInterval(-86400)
        
        for dirName in sessionDirs {
            // Skip sessions hidden by the user
            if hiddenSessions.contains(dirName) { continue }
            
            let sessionPath = "\(sessionStatePath)/\(dirName)"
            let eventsPath = "\(sessionPath)/events.jsonl"
            let workspacePath = "\(sessionPath)/workspace.yaml"
            
            guard fm.fileExists(atPath: eventsPath) else { continue }
            
            // Check file modification date — skip old and unchanged sessions
            guard let attrs = try? fm.attributesOfItem(atPath: eventsPath),
                  let modDate = attrs[.modificationDate] as? Date else { continue }
            
            if modDate < recentCutoff && !activeSessions.contains(dirName) { continue }
            
            // Skip if file hasn't changed since last check (unless it's a known active session)
            if let lastMod = lastModTimes[dirName], modDate <= lastMod,
               !activeSessions.contains(dirName) {
                continue
            }
            lastModTimes[dirName] = modDate
            
            // Read all events and evaluate state
            let (allEvents, _) = EventParser.readEvents(from: eventsPath, afterOffset: 0)
            guard !allEvents.isEmpty else { continue }
            
            if let (stateType, since) = EventParser.detectState(events: allEvents) {
                let workspace = WorkspaceInfo.parse(from: workspacePath)
                let summary = workspace?.summary ?? "Session \(dirName.prefix(8))"
                
                // For "working" state: only show if session has an active process
                if stateType == .working && !activeSessions.contains(dirName) {
                    // Not an active session, remove if present
                    if alerts.removeValue(forKey: dirName) != nil {
                        changed = true
                    }
                    continue
                }
                
                if alerts[dirName] == nil || alerts[dirName]?.alertType != stateType {
                    alerts[dirName] = SessionAlert(
                        id: dirName,
                        summary: summary,
                        alertType: stateType,
                        since: since
                    )
                    changed = true
                }
            } else {
                if alerts.removeValue(forKey: dirName) != nil {
                    changed = true
                }
            }
        }
        
        // Remove alerts for sessions that are no longer active and not needing attention
        let toRemove = alerts.keys.filter { id in
            alerts[id]?.alertType == .working && !activeSessions.contains(id)
        }
        for id in toRemove {
            alerts.removeValue(forKey: id)
            changed = true
        }
        
        if changed {
            onAlertsChanged?(Array(alerts.values))
        }
    }
}
