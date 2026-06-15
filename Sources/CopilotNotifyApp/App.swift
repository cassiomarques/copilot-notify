import AppKit
import SwiftUI
import CopilotNotifyLib

/// The main app delegate — wires everything together.
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController!
    private var sessionMonitor: SessionMonitor!
    private var notificationManager: NotificationManager!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon (pure menu bar app)
        NSApp.setActivationPolicy(.accessory)
        
        // Setup components
        statusBar = StatusBarController()
        sessionMonitor = SessionMonitor(pollInterval: 3.0)
        notificationManager = NotificationManager()
        notificationManager.setup()
        
        // Wire up: monitor → status bar + notifications
        sessionMonitor.onAlertsChanged = { [weak self] alerts in
            DispatchQueue.main.async {
                self?.statusBar.update(alerts: alerts)
                // Only notify for items needing attention, not "working"
                for alert in alerts where alert.alertType != .working {
                    self?.notificationManager.notify(alert: alert)
                }
            }
        }
        
        // Wire up: click alert → navigate to tmux pane (don't remove from list)
        statusBar.onAlertSelected = { alert in
            print("[CopilotNotify] Alert selected: \(alert.summary) (paneId: \(alert.tmuxPaneId ?? "nil"))")
            let navigated = TmuxNavigator.navigate(to: alert)
            if !navigated {
                print("[CopilotNotify] Navigation failed for session \(alert.id) — no tmux mapping found")
            }
        }
        
        // Wire up: dismiss alert
        statusBar.onAlertDismissed = { [weak self] alert in
            self?.sessionMonitor.dismiss(sessionId: alert.id)
            self?.notificationManager.clearSession(alert.id)
        }
        
        // Wire up: notification clicked → navigate
        notificationManager.onNotificationClicked = { [weak self] sessionId in
            guard let alert = self?.sessionMonitor.alerts[sessionId] else { return }
            if TmuxNavigator.navigate(to: alert) {
                self?.sessionMonitor.dismiss(sessionId: sessionId)
                self?.notificationManager.clearSession(sessionId)
            }
        }
        
        // Periodically update tmux mappings
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.sessionMonitor.updateTmuxMappings()
        }
        
        // Start monitoring
        sessionMonitor.start()
        
        print("[CopilotNotify] Started. Monitoring sessions...")
    }
}

@main
struct CopilotNotifyApp {
    static func main() {
        // Single-instance guard: exit if another instance is already running
        let runningCount = NSRunningApplication.runningApplications(withBundleIdentifier: "com.cassiomarques.CopilotNotify").count
        if runningCount > 1 {
            print("[CopilotNotify] Another instance is already running. Exiting.")
            return
        }
        // For debug builds without bundle ID, check by process name
        let myPid = ProcessInfo.processInfo.processIdentifier
        let output = shell("pgrep -f CopilotNotify")
        let pids = output.components(separatedBy: .newlines).compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let otherPids = pids.filter { $0 != myPid }
        if !otherPids.isEmpty {
            print("[CopilotNotify] Another instance is already running (PIDs: \(otherPids)). Exiting.")
            return
        }
        
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
    
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
        } catch { return "" }
    }
}
