import AppKit
import SwiftUI

/// Manages the NSStatusItem (menu bar icon) and its popover.
public class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var alerts: [SessionAlert] = []
    
    public var onAlertSelected: ((SessionAlert) -> Void)?
    public var onAlertDismissed: ((SessionAlert) -> Void)?
    
    public override init() {
        super.init()
        setupStatusItem()
        setupPopover()
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
            statusItem.menu = nil  // Reset so left click works normally next time
        } else {
            togglePopover()
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 300)
        popover.behavior = .transient
        popover.animates = true
        updatePopoverContent()
    }
    
    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        
        if popover.isShown {
            popover.performClose(nil)
        } else {
            updatePopoverContent()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    
    /// Update the displayed alerts and refresh the UI.
    public func update(alerts: [SessionAlert]) {
        self.alerts = alerts
        let needsAttention = alerts.filter { $0.alertType != .working }.count
        updateIcon(count: needsAttention)
        if popover.isShown {
            updatePopoverContent()
        }
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
    
    private func updatePopoverContent() {
        let view = SessionListView(
            alerts: alerts,
            onSelect: { [weak self] alert in
                self?.popover.performClose(nil)
                self?.onAlertSelected?(alert)
            },
            onDismiss: { [weak self] alert in
                self?.onAlertDismissed?(alert)
            }
        )
        popover.contentViewController = NSHostingController(rootView: view)
    }
}
