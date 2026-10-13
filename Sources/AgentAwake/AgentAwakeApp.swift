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
        let delegate = AppDelegate(resumeAwakeOnReady: CommandLine.arguments.contains("--resume-awake-session"))
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private var displayedStatusSymbol: String?
    private var menuCoordinator: OptionsButton.Coordinator?
    private var helpWindow: NSWindow?
    private static let reopenNotification = Notification.Name("io.github.devnjw.AgentAwake.showControls")
    private let presentOnReopen: (() -> Void)?
    private var resumeAwakeOnReady: Bool

    init(presentOnReopen: (() -> Void)? = nil, resumeAwakeOnReady: Bool = false) {
        self.presentOnReopen = presentOnReopen
        self.resumeAwakeOnReady = resumeAwakeOnReady
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
        let coordinator = OptionsButton.Coordinator(OptionsButton(model: model,
            showHelp: { [weak self] in self?.showHelp() },
            turnOffDisplays: { [weak self] in self?.turnOffDisplays() }))
        menuCoordinator = coordinator
        statusItem.menu = coordinator.makeStatusMenu()
        updateStatusItem()
        model.onStatusChange = { [weak self] in
            guard let self else { return }
            if self.resumeAwakeOnReady && self.model.isReady {
                self.resumeAwakeOnReady = false
                self.model.start()
            }
            self.menuCoordinator?.refreshSettings()
            self.updateStatusItem()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(closeControls),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(closeControls),
            name: NSApplication.didResignActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(closeControls),
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
        // Guard heartbeats arrive every second. Replace the image only when
        // the actual status changes, without repainting an open menu selection.
        if displayedStatusSymbol != symbol {
            let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: "AgentAwake")
            icon?.isTemplate = true
            statusItem?.button?.image = icon
            displayedStatusSymbol = symbol
        }
        let tooltip = "AgentAwake · \(model.title)"
        if statusItem?.button?.toolTip != tooltip { statusItem?.button?.toolTip = tooltip }
    }
    @objc private func closeControls() {
        statusItem?.menu?.cancelTracking()
    }
    @objc private func reopenRequested() { showDashboard() }

    @objc private func otherApplicationActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        closeControls()
    }

    private func showDashboard() {
        if showNativeMenu() { return }
        // Hidden status items and clamshell display changes still use a real
        // NSMenu. Never create or activate a second controls window.
        guard let menu = statusItem.menu,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
              else { return }
        menu.update()
        let visible = screen.visibleFrame
        let pointer = NSEvent.mouseLocation
        let point = NSPoint(
            x: max(visible.minX + 8, min(pointer.x, visible.maxX - menu.size.width - 8)),
            y: max(visible.minY + min(menu.size.height, visible.height), min(pointer.y, visible.maxY)))
        menu.popUp(positioning: nil, at: point, in: nil)
    }

    private func showNativeMenu() -> Bool {
        guard statusItem.isVisible, let button = statusItem.button,
              !button.isHiddenOrHasHiddenAncestor, let window = button.window else { return false }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard !anchor.isEmpty,
              NSScreen.screens.contains(where: { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) })
              else { return false }
        // NSStatusItem owns menu tracking and the selected background. Do not
        // activate the app or manually draw a pressed state on this path.
        button.performClick(nil)
        return true
    }
    private func showHelp() {
        closeControls()
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
        closeControls()
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
