import SwiftUI
import AppKit

struct DashboardView: View {
    @ObservedObject var model: AppModel
    let showHelp: () -> Void
    private let accent = Color(red: 0.62, green: 0.61, blue: 0.98)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Keep awake").font(.system(size: 15, weight: .medium))
                Spacer(minLength: 0)
                Toggle("Keep awake while plugged in", isOn: Binding(get: { model.enabled }, set: { $0 ? model.start() : model.stop() }))
                    .labelsHidden().toggleStyle(.switch).tint(accent)
                    .help("Keep awake while plugged in")
                    .disabled(!model.enabled && !model.isReady)
                Menu {
                    Picker("Stop after", selection: Binding(get: { model.duration }, set: { model.setDuration($0) })) {
                        Text("Until stopped").tag(0)
                        Text("1 hour").tag(3600)
                        Text("2 hours").tag(7200)
                        Text("4 hours").tag(14400)
                        Text("8 hours").tag(28800)
                    }
                    .pickerStyle(.inline)
                    if model.enabled && model.duration > 0 {
                        Text(model.durationLabel)
                    }
                    Divider()
                    Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLogin($0) }))
                    Divider()
                    Button("About & help", action: showHelp)
                    Button("Quit AgentAwake") { NSApp.terminate(nil) }.keyboardShortcut("q")
                } label: {
                    Image(systemName: "ellipsis").frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Options").help("Options")
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
        .alert("Login setting", isPresented: Binding(get: { model.settingsError != nil }, set: { if !$0 { model.settingsError = nil } })) {
            Button("OK") { model.settingsError = nil }
        } message: { Text(model.settingsError ?? "") }
    }
}

struct HelpView: View {
    let dismiss: () -> Void
    @State private var showCompatibility = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Keep local work running with the lid closed. Turn on Keep awake, then connect your charger.")
                    Text("Unplugging or high temperatures pause the session. It resumes when conditions allow. Quitting turns it off.")
                    Text("Use on a ventilated surface, never inside a bag.").foregroundStyle(.primary)
                    DisclosureGroup("Compatibility", isExpanded: $showCompatibility) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Lid control uses a private macOS API. Test a short session after OS updates. Avoid running other sleep utilities at the same time.")
                            Text("If both the app and its monitor are force-quit, restart your Mac to clear any remaining override. Network interruptions and agent approval prompts still require attention.")
                        }.padding(.top, 10)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Done", action: dismiss).keyboardShortcut(.defaultAction)
            }
        }
        .font(.system(size: 13)).foregroundStyle(.secondary)
        .padding(24).frame(width: 380, height: showCompatibility ? 490 : 290)
    }
}
