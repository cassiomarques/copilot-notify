import Foundation
import UserNotifications

/// Manages macOS system notifications for session alerts.
public class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    
    private var notifiedSessions: Set<String> = []
    private var hasBundleId: Bool = false
    
    /// Callback when user clicks a notification — provides session ID.
    public var onNotificationClicked: ((String) -> Void)?
    
    public func setup() {
        hasBundleId = Bundle.main.bundleIdentifier != nil
        
        if hasBundleId {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error = error {
                    print("[CopilotNotify] Notification auth error: \(error)")
                }
            }
        } else {
            print("[CopilotNotify] No bundle identifier — using osascript for notifications")
        }
    }
    
    /// Send a notification for a new alert (only once per session until dismissed).
    public func notify(alert: SessionAlert) {
        // Don't notify for "working" state
        guard alert.alertType != .working else { return }
        guard !notifiedSessions.contains(alert.id) else { return }
        notifiedSessions.insert(alert.id)
        
        if hasBundleId {
            sendUNNotification(alert: alert)
        } else {
            sendOsascriptNotification(alert: alert)
        }
    }
    
    /// Clear notification tracking for a dismissed session.
    public func clearSession(_ sessionId: String) {
        notifiedSessions.remove(sessionId)
        guard hasBundleId else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["copilot-\(sessionId)"])
    }
    
    // MARK: - UNUserNotificationCenter (bundled app)
    
    private func sendUNNotification(alert: SessionAlert) {
        let content = UNMutableNotificationContent()
        content.title = "Copilot: \(alert.summary)"
        content.body = bodyText(for: alert.alertType)
        content.sound = .default
        content.userInfo = ["sessionId": alert.id]
        content.categoryIdentifier = "COPILOT_ALERT"
        
        let request = UNNotificationRequest(
            identifier: "copilot-\(alert.id)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[CopilotNotify] Failed to deliver notification: \(error)")
            }
        }
    }
    
    // MARK: - osascript fallback (debug builds without bundle)
    
    private func sendOsascriptNotification(alert: SessionAlert) {
        let title = "Copilot: \(alert.summary)"
        let body = bodyText(for: alert.alertType)
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedBody = body.replacingOccurrences(of: "\"", with: "\\\"")
        
        let script = "display notification \"\(escapedBody)\" with title \"\(escapedTitle)\" sound name \"default\""
        
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }
    
    private func bodyText(for type: AlertType) -> String {
        switch type {
        case .completion: return "✅ Task completed"
        case .question: return "❓ Waiting for your input"
        case .approval: return "📋 Plan needs approval"
        case .working: return "⚙️ Working"
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let sessionId = response.notification.request.content.userInfo["sessionId"] as? String ?? ""
        if !sessionId.isEmpty {
            onNotificationClicked?(sessionId)
        }
        completionHandler()
    }
    
    // Show notifications even when app is in foreground
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
