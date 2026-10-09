import AppKit
import SwiftUI
import ServiceManagement
import AgentAwakeCore
import os

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
    @Published private(set) var reconnecting = false
    private let executableURL: URL?
    private let arguments: [String]
    private let clock: () -> TimeInterval
    private let restoreSleep: () throws -> Void
    private var child: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var timer: Timer?
    private var lastReply: TimeInterval = 0
    private var healthySince: TimeInterval?
    private var reconnectAt: TimeInterval?
    private var retiringAt: TimeInterval?
    private var recoveryAttempts = 0
    private var restoreAfterExit = false
    private var fatalRestoreError = false
    private var sleeping = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var stopping = false
    private var activity: NSObjectProtocol?
    private var displaySleepProcess: Process?
    private let logger = Logger(subsystem: "io.github.devnjw.AgentAwake", category: "monitor")
    var onStatusChange: (() -> Void)?

    init(executableURL: URL? = Bundle.main.executableURL, arguments: [String] = ["--guard"],
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         restoreSleep: @escaping () throws -> Void = PowerController.emergencyRelease) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.clock = clock
        self.restoreSleep = restoreSleep
    }

    var active: Bool { enabled && status?.active == true && error == nil }
    var isReady: Bool { child?.isRunning == true && status != nil && error == nil }
    var canRetry: Bool { error != nil && !fatalRestoreError }
    // A start request can render before the guard replaces its idle snapshot.
    // Keep the idle presentation until the guard reports the actual outcome.
    var awaitingStartConfirmation: Bool {
        enabled && (status?.reason == .disabled || status?.reason == .expired)
    }
    var title: String {
        if error != nil { return "Needs attention" }
        if reconnecting { return "Reconnecting…" }
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
            sendStart()
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
        guard child == nil, !stopping, !fatalRestoreError else { return }
        signal(SIGPIPE, SIG_IGN)
        setupMonitoring()
        guard let executable = executableURL else { fail("App file missing. Reinstall AgentAwake."); return }
        let process = Process()
        let incoming = Pipe(), outgoing = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = incoming
        process.standardOutput = outgoing
        process.standardError = FileHandle.standardError
        process.terminationHandler = { [weak self] process in
            Self.onMainRunLoop {
                guard let self, self.child === process, !self.stopping else { return }
                self.monitorExited(process)
            }
        }
        outgoing.fileHandleForReading.readabilityHandler = { [weak self, weak process] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            Self.onMainRunLoop {
                guard let self, let process, self.child === process, !self.stopping else { return }
                if data.isEmpty { self.recover("Monitor pipe closed") }
                else if self.retiringAt == nil { self.receive(data) }
            }
        }
        do {
            try process.run()
            child = process; input = incoming.fileHandleForWriting; output = outgoing.fileHandleForReading
            // Do not retain the child's ends in the parent; EOF is our crash signal.
            try? incoming.fileHandleForReading.close()
            try? outgoing.fileHandleForWriting.close()
            buffer.removeAll()
            status = nil
            reconnectAt = nil
            lastReply = clock()
            send(GuardCommand("configure", powerMode: powerMode))
            logger.info("Monitor started: \(process.processIdentifier)")
        } catch {
            outgoing.fileHandleForReading.readabilityHandler = nil
            logger.error("Monitor launch failed: \(error.localizedDescription, privacy: .public)")
            scheduleReconnect()
        }
    }

    private func setupMonitoring() {
        guard timer == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
            reason: "AgentAwake guard heartbeat")
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) { [weak self] _ in
            Self.onMainRunLoop { self?.workspaceWillSleep() }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
            Self.onMainRunLoop { self?.workspaceDidWake() }
        })
    }

    func workspaceWillSleep() { sleeping = true }

    func workspaceDidWake() {
        guard !stopping else { return }
        sleeping = false
        now = Date()
        lastReply = clock()
        if enabled {
            if remainingSeconds == 0 { stop() }
            else if retiringAt == nil { sendStart() }
        }
        if child == nil, canRetry {
            recoveryAttempts = 0
            scheduleReconnect()
        } else if retiringAt == nil { send(GuardCommand("heartbeat")) }
    }

    private var remainingSeconds: TimeInterval? {
        guard duration > 0, let startedAt else { return nil }
        return max(0, Double(duration) - Date().timeIntervalSince(startedAt))
    }

    private func sendStart() {
        if remainingSeconds == 0 { stop(); return }
        send(GuardCommand("start", seconds: remainingSeconds))
    }

    private func fail(_ message: String) {
        enabled = false
        reconnecting = false
        reconnectAt = nil
        error = message
        onStatusChange?()
    }

    private func recover(_ reason: String) {
        guard !stopping, retiringAt == nil, !fatalRestoreError else { return }
        logger.error("Monitor reconnect requested: \(reason, privacy: .public)")
        restoreAfterExit = enabled || status?.lidControlAccepted == true
        reconnecting = true
        error = nil
        status = nil
        healthySince = nil
        try? input?.close(); input = nil
        if let child {
            if child.isRunning {
                retiringAt = clock()
                child.terminate()
            } else { monitorExited(child) }
        } else { scheduleReconnect() }
        onStatusChange?()
    }

    private func monitorExited(_ process: Process) {
        let needsRestore = restoreAfterExit || enabled || status?.lidControlAccepted == true
        let exitStatus = process.terminationStatus
        child = nil
        try? input?.close(); input = nil
        output?.readabilityHandler = nil; output = nil
        buffer.removeAll()
        status = nil
        retiringAt = nil
        healthySince = nil
        restoreAfterExit = false
        // Normal exit runs the guard's cleanup, preserving an existing display mode.
        // A killed guard cannot release its private lid override itself.
        if exitStatus != 0 && exitStatus != 2 && needsRestore {
            do { try restoreSleep() }
            catch {
                fatalRestoreError = true
                fail("Couldn't restore sleep. Restart your Mac.")
                return
            }
        }
        if exitStatus == 2 {
            fail("AgentAwake is already running. Close the other copy.")
            return
        }
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard !stopping, !fatalRestoreError else { return }
        guard recoveryAttempts < 3 else {
            fail("Connection lost. Toggle Keep awake to retry.")
            return
        }
        recoveryAttempts += 1
        reconnecting = true
        error = nil
        reconnectAt = clock() + pow(2, Double(recoveryAttempts - 1))
        onStatusChange?()
    }

    // NSMenu tracks in a nested event loop that can defer main-queue Tasks.
    // Deliver monitor replies in common modes, matching the heartbeat timer.
    private nonisolated static func onMainRunLoop(_ action: @escaping @MainActor () -> Void) {
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
            MainActor.assumeIsolated { action() }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        if buffer.count > 65536 { recover("Invalid monitor response"); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
            guard let next = try? JSONDecoder().decode(GuardStatus.self, from: line) else {
                recover("Invalid monitor response"); return
            }
            let resume = reconnecting && enabled
            reconnecting = false
            status = next; lastReply = clock()
            if healthySince == nil { healthySince = lastReply }
            if next.reason == .error { error = next.message; enabled = false }
            if next.reason == .unsupported { error = "Lid control isn't available on this Mac."; enabled = false }
            if next.reason == .expired { enabled = false }
            if resume && next.reason == .disabled { sendStart() }
            onStatusChange?()
            if retiringAt != nil { return }
        }
    }

    func tick() {
        now = Date()
        if enabled && remainingSeconds == 0 { stop() }
        guard !sleeping, !stopping else { return }
        let uptime = clock()
        if let retiringAt, let child {
            if !child.isRunning { monitorExited(child) }
            else if uptime - retiringAt >= 2 { kill(child.processIdentifier, SIGKILL) }
            return
        }
        if child == nil {
            if let reconnectAt, uptime >= reconnectAt { connect() }
            return
        }
        if uptime - lastReply > 6 { recover("Monitor reply timeout"); return }
        if let healthySince, uptime - healthySince >= 30 { recoveryAttempts = 0 }
        send(GuardCommand("heartbeat"))
    }

    func start() {
        guard isReady || canRetry else { return }
        let retry = !isReady
        error = nil; enabled = true; now = Date(); startedAt = now
        if retry {
            recoveryAttempts = 0
            recover("User retry")
        } else { sendStart() }
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
        catch { recover("Monitor write failed") }
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
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll()
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
