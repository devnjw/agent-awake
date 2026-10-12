import AppKit
import SwiftUI

// SwiftUI Menu inside an NSPopover can become a one-row scrolling menu.
// Display a stable NSMenu below the button without the popover's height constraint.
struct OptionsButton: NSViewRepresentable {
    let model: AppModel
    let showHelp: () -> Void
    let turnOffDisplays: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> ScreenMenuButton {
        let button = ScreenMenuButton(frame: .zero, pullsDown: true)
        button.showMenu = { [weak button, weak coordinator = context.coordinator] in
            if let button { coordinator?.openMenu(button) }
        }
        button.menu = context.coordinator.makeMenu()
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.focusRingType = .none
        button.contentTintColor = .labelColor
        button.toolTip = "Options"
        button.setAccessibilityLabel("Options")
        return button
    }

    func updateNSView(_ button: ScreenMenuButton, context: Context) {
        // Keep callbacks current without rebuilding a menu while it is tracking.
        context.coordinator.parent = self
    }

    @MainActor final class Coordinator: NSObject, NSMenuDelegate {
        var parent: OptionsButton
        private var tracking = false
        private var statusMenu: NSMenu?
        private enum Setting { case awake, power, login, duration(Int) }
        private var settings: [(Setting, NSControl, NSMenuItem)] = []

        init(_ parent: OptionsButton) { self.parent = parent }

        func openMenu(_ button: ScreenMenuButton) {
            guard !tracking else { return }
            tracking = true
            DispatchQueue.main.async { [self, weak button] in
                defer { tracking = false }
                guard let button, let window = button.window else { return }
                let menu = makeMenu()
                button.menu = menu
                let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
                let screen = window.screen?.visibleFrame ?? rect
                let width = menu.size.width
                // Open toward the right, shifting left only at the screen edge.
                let x = max(screen.minX + 8, min(rect.minX, screen.maxX - width - 8))
                let y = min(rect.minY - 4, screen.maxY - 8)
                // Position the top edge in screen coordinates. A nil view
                // disconnects menu placement from the small popover window.
                menu.popUp(positioning: nil, at: NSPoint(x: x, y: y), in: nil)
            }
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            guard !tracking else { return }
            menu.removeAllItems()
            if menu === statusMenu { populateStatusMenu(menu) }
            else { populate(menu) }
        }

        func menuWillOpen(_ menu: NSMenu) { tracking = true }
        func menuDidClose(_ menu: NSMenu) { tracking = false }

        func makeMenu() -> NSMenu {
            let menu = NSMenu(title: "Options")
            menu.autoenablesItems = false
            menu.delegate = self
            populate(menu)
            return menu
        }

        func makeStatusMenu() -> NSMenu {
            let menu = NSMenu(title: "AgentAwake")
            menu.autoenablesItems = false
            menu.delegate = self
            statusMenu = menu
            populateStatusMenu(menu)
            return menu
        }

        private func populateStatusMenu(_ menu: NSMenu) {
            settings.removeAll()
            menu.addItem(settingItem("Keep awake", #selector(toggleAwake(_:)), kind: .awake, asSwitch: true))
            menu.addItem(.separator())
            populate(menu, persistent: true)
            refreshSettings()
        }

        @objc private func toggleAwake(_ sender: NSControl) {
            if parent.model.enabled { parent.model.stop() }
            else { parent.model.start() }
            refreshSettings()
        }

        private func populate(_ menu: NSMenu, persistent: Bool = false) {
            let model = parent.model
            // Pull-down buttons display the first item on the button, and hide
            // it from the open menu. Keep the icon out of the command list.
            let label = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            label.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Options")
            label.isHidden = true
            menu.addItem(label)
            menu.addItem(item("Turn off displays", #selector(sleepDisplays)))
            menu.addItem(.separator())
            menu.addItem(persistent
                ? settingItem("Only when plugged in", #selector(changePower(_:)), kind: .power)
                : item("Only when plugged in", #selector(changePower(_:)), checked: model.powerMode == .pluggedInOnly))
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "Stop after"))
            for (title, seconds) in [("Until stopped", 0), ("1 hour", 3600), ("2 hours", 7200), ("4 hours", 14400), ("8 hours", 28800)] {
                let option = persistent
                    ? settingItem(title, #selector(changeDuration(_:)), kind: .duration(seconds), radio: true)
                    : item(title, #selector(changeDuration(_:)), checked: model.duration == seconds)
                option.tag = seconds
                (option.view?.subviews.first as? NSControl)?.tag = seconds
                menu.addItem(option)
            }
            if model.enabled && model.duration > 0 {
                let remaining = NSMenuItem(title: model.durationLabel, action: nil, keyEquivalent: "")
                remaining.isEnabled = false
                menu.addItem(remaining)
            }
            menu.addItem(.separator())
            menu.addItem(persistent
                ? settingItem("Launch at login", #selector(changeLogin(_:)), kind: .login)
                : item("Launch at login", #selector(changeLogin(_:)), checked: model.launchAtLogin))
            menu.addItem(.separator())
            menu.addItem(item("About & help", #selector(help)))
            let quit = item("Quit AgentAwake", #selector(quitApp))
            quit.keyEquivalent = "q"
            quit.keyEquivalentModifierMask = .command
            menu.addItem(quit)
        }

        private func item(_ title: String, _ action: Selector, checked: Bool = false) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.state = checked ? .on : .off
            return item
        }

        private func settingItem(_ title: String, _ action: Selector, kind: Setting,
                                 asSwitch: Bool = false, radio: Bool = false) -> NSMenuItem {
            // A custom item view dispatches control actions directly, without
            // selecting a command and dismissing the native menu tracking loop.
            let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let row = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 30))
            let control: NSControl
            if asSwitch {
                let toggle = NSSwitch(frame: NSRect(x: 198, y: 2, width: 44, height: 26))
                toggle.target = self; toggle.action = action
                toggle.setAccessibilityLabel(title)
                control = toggle
                row.addSubview(toggle)
                let label = NSTextField(labelWithString: title)
                label.frame = NSRect(x: 14, y: 6, width: 170, height: 20)
                row.addSubview(label)
            } else {
                let button = NSButton(checkboxWithTitle: title, target: self, action: action)
                if radio { button.setButtonType(.radio) }
                button.frame = NSRect(x: 14, y: 4, width: 232, height: 22)
                control = button
                row.addSubview(button)
            }
            entry.view = row
            settings.append((kind, control, entry))
            return entry
        }

        func refreshSettings() {
            let model = parent.model
            for (kind, control, entry) in settings {
                let checked: Bool
                switch kind {
                case .awake: checked = model.enabled
                case .power: checked = model.powerMode == .pluggedInOnly
                case .login: checked = model.launchAtLogin
                case .duration(let seconds): checked = model.duration == seconds
                }
                let state: NSControl.StateValue = checked ? .on : .off
                if entry.state != state { entry.state = state }
                if let toggle = control as? NSSwitch, toggle.state != state { toggle.state = state }
                if let button = control as? NSButton, button.state != state { button.state = state }
                let isAwake: Bool
                if case .awake = kind { isAwake = true } else { isAwake = false }
                let enabled = !(isAwake && !model.enabled && !model.isReady && !model.canRetry)
                if control.isEnabled != enabled { control.isEnabled = enabled }
            }
        }

        @objc private func sleepDisplays() { parent.turnOffDisplays() }
        @objc private func changePower(_ sender: Any?) {
            parent.model.setPowerMode(parent.model.powerMode == .pluggedInOnly ? .anyPower : .pluggedInOnly)
            refreshSettings()
        }
        @objc private func changeDuration(_ sender: Any) {
            let seconds = (sender as? NSControl)?.tag ?? (sender as? NSMenuItem)?.tag ?? 0
            parent.model.setDuration(seconds)
            refreshSettings()
        }
        @objc private func changeLogin(_ sender: Any?) {
            parent.model.setLogin(!parent.model.launchAtLogin)
            refreshSettings()
        }
        @objc private func help() { parent.showHelp() }
        @objc private func quitApp() { NSApp.terminate(nil) }
    }

    // Keep the native menu-button accessibility and keyboard behavior, while
    // replacing the cell's window-relative popup placement.
    @MainActor final class ScreenMenuButton: NSPopUpButton {
        var showMenu: (() -> Void)?
        override func mouseDown(with event: NSEvent) { showMenu?() }
        override func performClick(_ sender: Any?) { showMenu?() }
        override func accessibilityPerformPress() -> Bool { showMenu?(); return true }
    }
}
