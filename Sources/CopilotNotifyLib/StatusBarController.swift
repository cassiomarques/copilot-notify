import AppKit
import SwiftUI

/// Manages the NSStatusItem (menu bar icon) and toggles the session window.
public class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private let sessionWindow: SessionWindow
    
    public var onAlertSelected: ((SessionAlert) -> Void)? {
        get { sessionWindow.onAlertSelected }
        set { sessionWindow.onAlertSelected = newValue }
    }
    public var onAlertDismissed: ((SessionAlert) -> Void)? {
        get { sessionWindow.onAlertDismissed }
        set { sessionWindow.onAlertDismissed = newValue }
    }
    
    public override init() {
        self.sessionWindow = SessionWindow()
        super.init()
        setupStatusItem()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            updateIcon(count: 0)
            button.action = #selector(handleClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // Right-click context menu
        let menu = NSMenu()
        menu.autoenablesItems = false
        let quitItem = NSMenuItem(title: "Quit Copilot Notify", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)
        rightClickMenu = menu
    }
    
    private var rightClickMenu: NSMenu?
    
    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            statusItem.menu = rightClickMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            sessionWindow.toggle()
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    /// Update the displayed alerts and refresh the UI.
    public func update(alerts: [SessionAlert]) {
        let needsAttention = alerts.filter { $0.alertType == .question || $0.alertType == .approval }.count
        updateIcon(count: needsAttention)
        sessionWindow.update(alerts: alerts)
    }
    
    private func updateIcon(count: Int) {
        guard let button = statusItem.button else { return }
        
        if count == 0 {
            button.image = NSImage(systemSymbolName: "bell", accessibilityDescription: "Copilot Notify")
            button.title = ""
        } else {
            button.image = NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: "Copilot Notify - \(count) alerts")
            button.title = " \(count)"
        }
        
        button.image?.size = NSSize(width: 18, height: 18)
        button.image?.isTemplate = true
    }
}
