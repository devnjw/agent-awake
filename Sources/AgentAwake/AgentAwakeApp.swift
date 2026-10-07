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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second launch focuses the existing instance instead of starting another guard.
        if let identifier = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
               .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: [.activateAllWindows]); NSApp.terminate(nil); return
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
        model.connect()
        showPopover()
    }
    private func updateStatusItem() {
        let symbol = model.error != nil ? "exclamationmark.circle" : (model.active ? "bolt.fill" : "bolt")
        let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: "AgentAwake: \(model.title)")
        icon?.isTemplate = true
        statusItem?.button?.image = icon
        statusItem?.button?.toolTip = "AgentAwake · \(model.title)"
    }
    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else { showPopover() }
    }
    private func showPopover() {
        guard !popover.isShown else { return }
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    private func showHelp() {
        popover.performClose(nil)
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
        popover.performClose(nil)
        // Let the menu dismiss and its mouse-up finish before sleeping displays.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.model.turnOffDisplays { [weak self] succeeded in
                if !succeeded { self?.showPopover() }
            }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover(); return true
    }
    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
