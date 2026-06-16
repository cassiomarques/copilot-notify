import AppKit
import SwiftUI

/// A regular window that shows the session list.
public class SessionWindow {
    private var window: NSWindow!
    private var hostingView: NSHostingView<SessionListView>!
    private var alerts: [SessionAlert] = []
    
    public var onAlertSelected: ((SessionAlert) -> Void)?
    public var onAlertDismissed: ((SessionAlert) -> Void)?
    
    public init() {
        setupWindow()
    }
    
    private func setupWindow() {
        let contentRect = NSRect(x: 0, y: 0, width: 360, height: 400)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Copilot Sessions"
        window.level = .normal
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("CopilotNotifySessionWindow")
        window.minSize = NSSize(width: 300, height: 200)
        
        // Set initial content
        let view = makeSessionListView()
        hostingView = NSHostingView(rootView: view)
        window.contentView = hostingView
    }
    
    /// Toggle window visibility.
    public func toggle() {
        if window.isVisible {
            window.orderOut(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            if !window.frameAutosaveName.isEmpty,
               UserDefaults.standard.string(forKey: "NSWindow Frame \(window.frameAutosaveName)") == nil {
                window.center()
            }
        }
    }
    
    /// Show the window.
    public func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
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
