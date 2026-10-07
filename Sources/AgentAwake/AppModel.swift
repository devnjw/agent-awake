import AppKit
import SwiftUI
import ServiceManagement
import AgentAwakeCore

@MainActor final class AppModel: ObservableObject {
    @Published var status: GuardStatus?
    @Published var enabled = false
    @Published var duration = 0
    @Published private(set) var powerMode = PowerMode(rawValue: UserDefaults.standard.string(forKey: "powerMode") ?? "") ?? .pluggedInOnly
    @Published var startedAt: Date?
    @Published var error: String?
    @Published var settingsError: String?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var now = Date()
    private var child: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var timer: Timer?
    private var lastReply = Date()
    private var stopping = false
    private var activity: NSObjectProtocol?
    private var displaySleepProcess: Process?
    var onStatusChange: (() -> Void)?

    var active: Bool { enabled && status?.active == true && error == nil }
    var isReady: Bool { child?.isRunning == true && status != nil && error == nil }
    // A start request can render before the guard replaces its idle snapshot.
    // Keep the idle presentation until the guard reports the actual outcome.
    var awaitingStartConfirmation: Bool {
        enabled && (status?.reason == .disabled || status?.reason == .expired)
    }
    var title: String {
        if error != nil { return "Needs attention" }
        if active { return "Awake" }
        if awaitingStartConfirmation { return "Keep awake" }
        if enabled {
            switch status?.reason {
            case .battery: return "Waiting for power"
            case .thermal: return "Paused · Too warm"
            default: return "Checking power…"
            }
        }
        switch status?.power {
        case .ac: return "Power connected"
        case .battery: return "On battery"
        default: return "Checking power…"
        }
    }
    var durationLabel: String {
        guard duration > 0 else { return "Until stopped" }
        guard enabled, let startedAt else { return "\(duration / 3600)h" }
        let minutes = max(0, Int(ceil((Double(duration) - now.timeIntervalSince(startedAt)) / 60)))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m left" : "\(minutes)m left"
    }
    func setDuration(_ seconds: Int) {
        duration = seconds
        // Editing an active session starts the selected interval from now.
        if enabled {
            now = Date(); startedAt = now
            send(GuardCommand("start", seconds: seconds == 0 ? nil : Double(seconds)))
        }
    }

    func setPowerMode(_ mode: PowerMode) {
        powerMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "powerMode")
        // Reevaluate the current session without restarting its deadline.
        send(GuardCommand("configure", powerMode: mode))
    }

    func turnOffDisplays(completion: @escaping (Bool) -> Void) {
        guard displaySleepProcess == nil, !stopping else { return }
        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        process.terminationHandler = { [weak self] process in
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let succeeded = process.terminationStatus == 0 && message.isEmpty
            Task { @MainActor in
                guard let self else { return }
                self.displaySleepProcess = nil
                guard !self.stopping else { return }
                if !succeeded { self.settingsError = "Couldn't turn off displays. \(message)" }
                completion(succeeded)
            }
        }
        do {
            try process.run()
            displaySleepProcess = process
            try? errors.fileHandleForWriting.close()
        } catch {
            settingsError = "Couldn't turn off displays: \(error.localizedDescription)"
            completion(false)
        }
    }

    func connect() {
        guard child == nil else { return }
        signal(SIGPIPE, SIG_IGN)
        guard let executable = Bundle.main.executableURL else { error = "App file missing. Reinstall AgentAwake."; return }
        let process = Process()
        let incoming = Pipe(), outgoing = Pipe()
        process.executableURL = executable
        process.arguments = ["--guard"]
        process.standardInput = incoming
        process.standardOutput = outgoing
        process.standardError = FileHandle.standardError
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self, !self.stopping else { return }
                let needsRecovery = process.terminationStatus != 2 && (self.enabled || self.status?.lidControlAccepted == true)
                self.enabled = false
                self.error = "Monitor stopped. Reopen AgentAwake."
                // A killed guard cannot run its own defer. The surviving UI clears its override.
                do { if needsRecovery { try PowerController.emergencyRelease() } }
                catch { self.error = "Couldn't restore sleep. Restart your Mac." }
                self.onStatusChange?()
            }
        }
        outgoing.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            Task { @MainActor in self?.receive(data) }
        }
        do {
            try process.run()
            // Crucial: do not retain the child's ends in the parent; EOF is our crash signal.
            try incoming.fileHandleForReading.close()
            try outgoing.fileHandleForWriting.close()
            child = process; input = incoming.fileHandleForWriting; output = outgoing.fileHandleForReading
            send(GuardCommand("configure", powerMode: powerMode))
            lastReply = Date()
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "AgentAwake guard heartbeat")
            let clock = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            RunLoop.main.add(clock, forMode: .common)
            timer = clock
        } catch { self.error = "Couldn't start monitor: \(error.localizedDescription)" }
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        if buffer.count > 65536 { error = "Invalid monitor response. Reopen AgentAwake."; stop(); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
            guard let next = try? JSONDecoder().decode(GuardStatus.self, from: line) else { continue }
            status = next; lastReply = Date()
            if next.reason == .error { error = next.message; enabled = false }
            if next.reason == .unsupported { error = "Lid control isn't available on this Mac."; enabled = false }
            if next.reason == .expired {
                enabled = false
            }
            onStatusChange?()
        }
    }

    private func tick() {
        now = Date()
        if Date().timeIntervalSince(lastReply) > 6 {
            if enabled { stop() }
            error = "Monitor isn't responding. Reopen AgentAwake."
            // Stop feeding a wedged child. Its 8-second lease then expires.
            try? input?.close(); input = nil
            return
        }
        send(GuardCommand("heartbeat"))
    }

    func start() {
        guard isReady else { return }
        error = nil; enabled = true; now = Date(); startedAt = now
        send(GuardCommand("start", seconds: duration == 0 ? nil : Double(duration)))
        onStatusChange?()
    }
    func stop() {
        enabled = false
        send(GuardCommand("stop"))
        onStatusChange?()
    }
    private func send(_ command: GuardCommand) {
        guard let input, let data = try? JSONEncoder().encode(command) else { return }
        do { try input.write(contentsOf: data + Data([10])) }
        catch { self.error = "Monitor disconnected. Reopen AgentAwake."; enabled = false }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin { SMAppService.openSystemSettingsLoginItems() }
        } catch { self.settingsError = "Couldn't update launch at login: \(error.localizedDescription)" }
    }
    func shutdown() {
        stopping = true
        timer?.invalidate()
        send(GuardCommand("quit"))
        try? input?.close(); input = nil
        // Let the guard restore before macOS tears down the UI process.
        let limit = Date().addingTimeInterval(2)
        while child?.isRunning == true && Date() < limit { Thread.sleep(forTimeInterval: 0.05) }
        if child?.isRunning == true { child?.terminate() }
        output?.readabilityHandler = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
    }
}
