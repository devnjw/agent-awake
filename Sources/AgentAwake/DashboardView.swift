import SwiftUI
import AppKit

struct DashboardView: View {
    @ObservedObject var model: AppModel
    let showHelp: () -> Void
    let turnOffDisplays: () -> Void
    private let accent = Color(red: 0.62, green: 0.61, blue: 0.98)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Keep awake").font(.system(size: 15, weight: .medium))
                Spacer(minLength: 0)
                Toggle("Keep awake", isOn: Binding(get: { model.enabled }, set: { $0 ? model.start() : model.stop() }))
                    .labelsHidden().toggleStyle(.switch).tint(accent)
                    .help(model.powerMode == .pluggedInOnly ? "Keep awake while plugged in" : "Keep awake on charger or battery")
                    .disabled(!model.enabled && !model.isReady && !model.canRetry)
                OptionsButton(model: model, showHelp: showHelp, turnOffDisplays: turnOffDisplays)
                    .frame(width: 24, height: 24)
            }

            if let error = model.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.enabled && !model.active && !model.awaitingStartConfirmation {
                Text(model.title)
                    .font(.system(size: 12)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16).frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
        .alert("AgentAwake", isPresented: Binding(get: { model.settingsError != nil }, set: { if !$0 { model.settingsError = nil } })) {
            Button("OK") { model.settingsError = nil }
        } message: { Text(model.settingsError ?? "") }
    }
}

struct HelpView: View {
    let dismiss: () -> Void
    private let repository = URL(string: "https://github.com/devnjw/agent-awake")!
    private let issues = URL(string: "https://github.com/devnjw/agent-awake/issues/new")!
    private var version: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            helpSection("Keep awake",
                "Keep work running with the lid closed. A charger is required by default; uncheck **Only when plugged in** to use battery. Quitting ends the session.")
            helpSection("Screens",
                "**Turn off displays** sleeps every screen without ending Keep awake. Keyboard, mouse, or trackpad input wakes them.")
            helpSection("Safe use",
                "High temperatures pause the session until the Mac cools. Use a ventilated surface, never inside a bag.")
            helpSection("Compatibility",
                "Test briefly after macOS updates. Avoid other sleep utilities. Restart your Mac if sleep stays abnormal after a forced quit.")

            Divider()

            HStack {
                Link("github.com/devnjw/agent-awake", destination: repository)
                    .help("Open the AgentAwake repository")
                Spacer()
                Link("Report an issue", destination: issues)
                    .help("Report a problem on GitHub")
            }
            .font(.system(size: 12))

            HStack {
                if let version {
                    Text("Version \(version)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done", action: dismiss).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func helpSection(_ title: String, _ text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
