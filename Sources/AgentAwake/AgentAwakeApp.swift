import AppKit
import SwiftUI
import AgentAwakeCore

@main enum AgentAwakeMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--guard") { SessionGuard().run() }
        if CommandLine.arguments.contains("--diagnose") {
            let power = PowerSnapshot.read()
            print("power=\(power.source.rawValue) battery=\(power.battery.map(String.init) ?? "unknown") lid=\(power.lidClosed.map(String.init) ?? "none") thermal=\(power.thermal)")
            print("SleepDisabled=\(rootBool("SleepDisabled").map(String.init) ?? "unknown")")
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var helpWindow: NSWindow?
    private var controlsPanel: NSPanel?
    private static let reopenNotification = Notification.Name("io.github.devnjw.AgentAwake.showControls")
    private let presentOnReopen: (() -> Void)?

    init(presentOnReopen: (() -> Void)? = nil) {
        self.presentOnReopen = presentOnReopen
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second launch focuses the existing instance instead of starting another guard.
        if let identifier = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
               .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: [.activateAllWindows])
            DistributedNotificationCenter.default().postNotificationName(Self.reopenNotification,
                object: String(existing.processIdentifier), userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil); return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        updateStatusItem()
        model.onStatusChange = { [weak self] in self?.updateStatusItem() }
        let hosting = NSHostingController(rootView: DashboardView(model: model,
            showHelp: { [weak self] in self?.showHelp() },
            turnOffDisplays: { [weak self] in self?.turnOffDisplays() }))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = false
        NotificationCenter.default.addObserver(self, selector: #selector(closePopover),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(closePopover),
            name: NSApplication.didResignActiveNotification, object: nil)
        if let window = statusItem.button?.window {
            NotificationCenter.default.addObserver(self, selector: #selector(closePopover),
                name: NSWindow.didMoveNotification, object: window)
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(closePopover),
            name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(otherApplicationActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(reopenRequested),
            name: Self.reopenNotification, object: String(ProcessInfo.processInfo.processIdentifier))
        model.connect()
        // Launch quietly. The status-item window may not have its final position
        // yet, especially after login or a display configuration change.
    }
    private func updateStatusItem() {
        let symbol = model.error != nil ? "exclamationmark.circle" : (model.active ? "bolt.fill" : "bolt")
        let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: "AgentAwake: \(model.title)")
        icon?.isTemplate = true
        statusItem?.button?.image = icon
        statusItem?.button?.toolTip = "AgentAwake · \(model.title)"
    }
    @objc private func togglePopover() {
        if popover.isShown || controlsPanel?.isVisible == true { closePopover() }
        else { showDashboard() }
    }
    @objc private func closePopover() {
        popover.performClose(nil)
        controlsPanel?.close()
    }
    @objc private func reopenRequested() { showDashboard() }

    @objc private func otherApplicationActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        closePopover()
    }

    private func showDashboard() {
        if showPopover() { controlsPanel?.close(); return }
        // In clamshell mode the status-item window may still reference the
        // disconnected built-in screen. Explicit open requests must remain usable.
        if controlsPanel == nil {
            let hosting = NSHostingController(rootView: DashboardView(model: model,
                showHelp: { [weak self] in self?.showHelp() },
                turnOffDisplays: { [weak self] in self?.turnOffDisplays() }))
            hosting.sizingOptions = [.preferredContentSize]
            let panel = NSPanel(contentViewController: hosting)
            panel.styleMask = [.titled, .closable, .utilityWindow]
            panel.title = "AgentAwake"
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            controlsPanel = panel
        }
        if let panel = controlsPanel,
           let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2,
                y: visible.midY - panel.frame.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        controlsPanel?.makeKeyAndOrderFront(nil)
    }

    private func showPopover() -> Bool {
        if popover.isShown { return true }
        guard statusItem.isVisible,
              let button = statusItem.button, !button.isHiddenOrHasHiddenAncestor,
              let window = button.window else { return false }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        // Use the live screen list, not a stale window.screen after lid closure.
        guard !anchor.isEmpty,
              NSScreen.screens.contains(where: { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) })
              else { return false }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        return true
    }
    private func showHelp() {
        closePopover()
        if helpWindow == nil {
            let hosting = NSHostingController(rootView: HelpView(dismiss: { [weak self] in self?.helpWindow?.close() }))
            hosting.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable]
            window.title = "About AgentAwake"
            window.isReleasedWhenClosed = false
            window.center()
            helpWindow = window
        }
        helpWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func turnOffDisplays() {
        closePopover()
        // Let the menu dismiss and its mouse-up finish before sleeping displays.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.model.turnOffDisplays { [weak self] succeeded in
                if !succeeded { self?.showDashboard() }
            }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Launch stays quiet, but explicit Raycast/Finder/Dock reopen requests
        // must show controls even when the status-item anchor is unavailable.
        if let presentOnReopen { presentOnReopen() }
        else { showDashboard() }
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        model.shutdown()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
