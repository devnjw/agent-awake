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
                let x = max(screen.minX + 8, min(rect.maxX - width, screen.maxX - width - 8))
                let y = min(rect.minY - 4, screen.maxY - 8)
                // Position the top edge in screen coordinates. A nil view
                // disconnects menu placement from the small popover window.
                menu.popUp(positioning: nil, at: NSPoint(x: x, y: y), in: nil)
            }
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            guard !tracking else { return }
            menu.removeAllItems()
            populate(menu)
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

        private func populate(_ menu: NSMenu) {
            let model = parent.model
            // Pull-down buttons display the first item on the button, and hide
            // it from the open menu. Keep the icon out of the command list.
            let label = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            label.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Options")
            label.isHidden = true
            menu.addItem(label)
            menu.addItem(item("Turn off displays", #selector(sleepDisplays)))
            menu.addItem(.separator())
            menu.addItem(item("Only when plugged in", #selector(changePower), checked: model.powerMode == .pluggedInOnly))
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "Stop after"))
            for (title, seconds) in [("Until stopped", 0), ("1 hour", 3600), ("2 hours", 7200), ("4 hours", 14400), ("8 hours", 28800)] {
                let option = item(title, #selector(changeDuration(_:)), checked: model.duration == seconds)
                option.tag = seconds
                menu.addItem(option)
            }
            if model.enabled && model.duration > 0 {
                let remaining = NSMenuItem(title: model.durationLabel, action: nil, keyEquivalent: "")
                remaining.isEnabled = false
                menu.addItem(remaining)
            }
            menu.addItem(.separator())
            menu.addItem(item("Launch at login", #selector(changeLogin), checked: model.launchAtLogin))
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

        @objc private func sleepDisplays() { parent.turnOffDisplays() }
        @objc private func changePower() {
            parent.model.setPowerMode(parent.model.powerMode == .pluggedInOnly ? .anyPower : .pluggedInOnly)
        }
        @objc private func changeDuration(_ item: NSMenuItem) { parent.model.setDuration(item.tag) }
        @objc private func changeLogin() { parent.model.setLogin(!parent.model.launchAtLogin) }
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
