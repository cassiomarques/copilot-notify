import AppKit
import SwiftUI

/// A floating panel that shows the session list. Non-activating so it doesn't steal focus.
public class SessionWindow {
    private var panel: NSPanel!
    private var hostingView: NSHostingView<SessionListView>!
    private var alerts: [SessionAlert] = []
    
    public var onAlertSelected: ((SessionAlert) -> Void)?
    public var onAlertDismissed: ((SessionAlert) -> Void)?
    
    public init() {
        setupPanel()
    }
    
    private func setupPanel() {
        let contentRect = NSRect(x: 0, y: 0, width: 360, height: 400)
        panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        
        panel.title = "Copilot Sessions"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.setFrameAutosaveName("CopilotNotifySessionWindow")
        panel.minSize = NSSize(width: 300, height: 200)
        
        // Set initial content
        let view = makeSessionListView()
        hostingView = NSHostingView(rootView: view)
        panel.contentView = hostingView
    }
    
    /// Toggle window visibility.
    public func toggle() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFront(nil)
            // If no saved position, center on screen
            if !panel.frameAutosaveName.isEmpty,
               UserDefaults.standard.string(forKey: "NSWindow Frame \(panel.frameAutosaveName)") == nil {
                panel.center()
            }
        }
    }
    
    /// Show the window.
    public func show() {
        panel.orderFront(nil)
    }
    
    /// Update the displayed alerts.
    public func update(alerts: [SessionAlert]) {
        self.alerts = alerts
        let view = makeSessionListView()
        hostingView.rootView = view
    }
    
    private func makeSessionListView() -> SessionListView {
        SessionListView(
            alerts: alerts,
            onSelect: { [weak self] alert in
                self?.onAlertSelected?(alert)
            },
            onDismiss: { [weak self] alert in
                self?.onAlertDismissed?(alert)
            }
        )
    }
}
