import Foundation
import UserNotifications

/// Manages macOS system notifications for session alerts.
public class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    
    private var notifiedSessions: Set<String> = []
    
    /// Callback when user clicks a notification — provides session ID.
    public var onNotificationClicked: ((String) -> Void)?
    
    public func setup() {
        // UNUserNotificationCenter requires a bundled app.
        // When running from a debug build without a bundle, skip setup gracefully.
        guard Bundle.main.bundleIdentifier != nil else {
            print("[CopilotNotify] No bundle identifier — notifications disabled (run as .app bundle to enable)")
            return
        }
        
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[CopilotNotify] Notification auth error: \(error)")
            }
        }
    }
    
    /// Send a notification for a new alert (only once per session until dismissed).
    public func notify(alert: SessionAlert) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        guard !notifiedSessions.contains(alert.id) else { return }
        notifiedSessions.insert(alert.id)
        
        let content = UNMutableNotificationContent()
        content.title = "Copilot: \(alert.summary)"
        content.body = bodyText(for: alert.alertType)
        content.sound = .default
        content.userInfo = ["sessionId": alert.id]
        
        // Category for actionable notification
        content.categoryIdentifier = "COPILOT_ALERT"
        
        let request = UNNotificationRequest(
            identifier: "copilot-\(alert.id)",
            content: content,
            trigger: nil  // deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[CopilotNotify] Failed to deliver notification: \(error)")
            }
        }
    }
    
    /// Clear notification tracking for a dismissed session.
    public func clearSession(_ sessionId: String) {
        notifiedSessions.remove(sessionId)
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["copilot-\(sessionId)"])
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
