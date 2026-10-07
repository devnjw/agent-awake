import Foundation
import IOKit.ps
import AgentAwakeCore
import Darwin

// An independent child owns all assertions and restores the lid flag on pipe EOF,
// missed heartbeats, SIGTERM, disallowed power sources, expiry, or thermal pressure.
// Nothing is installed as root, and no power-management preferences are written.
final class SessionGuard {
    private let controller = PowerController()
    private var policy = SessionPolicy(now: ProcessInfo.processInfo.systemUptime)
    private var input = Data()
    private var timer: DispatchSourceTimer?
    private var reader: DispatchSourceRead?
    private var signals: [DispatchSourceSignal] = []
    private var powerSource: CFRunLoopSource?
    private var lastStatus: GuardStatus?
    private var activity: NSObjectProtocol?
    private var lockFD: Int32 = -1

    func run() -> Never {
        signal(SIGPIPE, SIG_IGN)
        // One guard per user prevents two app copies from fighting over the shared flag.
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AgentAwake")
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        catch { exit(2) }
        lockFD = open(directory.appendingPathComponent("session.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            emit(GuardStatus(reason: .error, power: .unknown, battery: nil, lidClosed: nil,
                lidControlAccepted: false, assertionHeld: false, thermal: 0, message: "AgentAwake is already running."))
            exit(2)
        }
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Monitor AgentAwake power safety")
        for number in [SIGTERM, SIGINT, SIGHUP] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [weak self] in self?.finish() }
            source.resume(); signals.append(source)
        }
        let readSource = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
        readSource.setEventHandler { [weak self] in self?.readCommands() }
        readSource.resume(); reader = readSource
        let clock = DispatchSource.makeTimerSource(queue: .main)
        clock.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(100))
        clock.setEventHandler { [weak self] in self?.evaluate() }
        clock.resume(); timer = clock
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<SessionGuard>.fromOpaque(context).takeUnretainedValue().evaluate()
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue() {
            powerSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        RunLoop.main.run()
        finish()
    }

    private func readCommands() {
        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = Darwin.read(STDIN_FILENO, &bytes, bytes.count)
        if count == 0 { finish() }
        guard count > 0 else { return }
        input.append(contentsOf: bytes.prefix(count))
        if input.count > 65536 { finish() }
        while let newline = input.firstIndex(of: 10) {
            let line = Data(input[..<newline]); input.removeSubrange(...newline)
            guard let command = try? JSONDecoder().decode(GuardCommand.self, from: line) else { finish() }
            let now = ProcessInfo.processInfo.systemUptime
            policy.lastHeartbeat = now
            switch command.action {
            case "configure":
                if let mode = command.powerMode { policy.powerMode = mode }
            case "start":
                policy.enabled = true
                policy.deadline = command.seconds.flatMap { $0 > 0 && $0.isFinite ? now + $0 : nil }
            case "stop": policy.enabled = false
            case "heartbeat": break
            case "quit": finish()
            default: finish()
            }
            evaluate()
        }
    }

    private func evaluate() {
        let snapshot = PowerSnapshot.read()
        var reason = policy.reason(now: ProcessInfo.processInfo.systemUptime, power: snapshot.source,
            hot: snapshot.thermal >= ProcessInfo.ThermalState.serious.rawValue, hasLid: snapshot.lidClosed != nil)
        var message: String?
        do {
            if reason == .active { try controller.acquire(powerMode: policy.powerMode) }
            else { try controller.release() }
        } catch {
            reason = .error; message = error.localizedDescription; policy.enabled = false
        }
        if reason == .expired { policy.enabled = false }
        emit(GuardStatus(reason: reason, power: snapshot.source, battery: snapshot.battery,
            lidClosed: snapshot.lidClosed, lidControlAccepted: controller.lidControlAccepted,
            assertionHeld: controller.assertionHeld, thermal: snapshot.thermal, message: message))
        if reason == .disconnected { finish() }
    }

    private func emit(_ status: GuardStatus) {
        // Emit every evaluation so the UI can detect a dead or wedged guard.
        guard let data = try? JSONEncoder().encode(status) else { return }
        do { try FileHandle.standardOutput.write(contentsOf: data + Data([10])) }
        catch { finish() }
        lastStatus = status
    }

    private func finish() -> Never {
        // Retry transient release failures before exiting. A failed restore is not hidden.
        for _ in 0..<3 {
            do {
                try controller.release()
                if let activity { ProcessInfo.processInfo.endActivity(activity) }
                exit(0)
            } catch { Thread.sleep(forTimeInterval: 0.1) }
        }
        fputs("AgentAwake: lid state restoration failed. Restart the Mac to clear the transient override.\n", stderr)
        exit(3)
    }
}
