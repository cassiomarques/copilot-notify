import Foundation

/// The type of attention a session requires.
public enum AlertType: String, Codable {
    case completion   // Task finished
    case question     // Agent asked user a question (ask_user / elicitation)
    case approval     // Plan needs approval
    case working      // Agent is actively working (no attention needed)
}

/// Represents a session that needs the user's attention.
public struct SessionAlert: Identifiable {
    public let id: String           // session UUID
    public let summary: String      // human-readable session name
    public let alertType: AlertType
    public let since: Date          // when the alert was triggered
    public var tmuxTarget: String?  // e.g. "1:3.2" (session:window.pane)
    public var tmuxPaneId: String?  // e.g. "%33"
    public var tty: String?         // e.g. "ttys020"
    
    public init(id: String, summary: String, alertType: AlertType, since: Date,
                tmuxTarget: String? = nil, tmuxPaneId: String? = nil, tty: String? = nil) {
        self.id = id
        self.summary = summary
        self.alertType = alertType
        self.since = since
        self.tmuxTarget = tmuxTarget
        self.tmuxPaneId = tmuxPaneId
        self.tty = tty
    }
}
