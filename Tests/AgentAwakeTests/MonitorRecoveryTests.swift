import Foundation
import Testing
@testable import AgentAwake

// Exercises the real Process/pipes/run-loop connection without power assertions.
@Suite(.serialized) @MainActor
struct MonitorRecoveryTests {
    private final class Fixture {
        let directory: URL
        let script: URL

        init(_ behavior: String? = nil) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            script = directory.appendingPathComponent("monitor.sh")
            try Self.source.write(to: script, atomically: true, encoding: .utf8)
            if let behavior { try Data().write(to: directory.appendingPathComponent(behavior)) }
        }

        @MainActor func model(clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                   restoreSleep: @escaping () throws -> Void = {}) -> AppModel {
            AppModel(executableURL: URL(fileURLWithPath: "/bin/sh"),
                     arguments: [script.path, directory.path], clock: clock, restoreSleep: restoreSleep)
        }

        var launches: Int {
            Int((try? String(contentsOf: directory.appendingPathComponent("count"), encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        static let source = #"""
        directory="$1"
        count=0
        if [ -f "$directory/count" ]; then count=$(cat "$directory/count"); fi
        count=$((count + 1))
        printf '%s\n' "$count" > "$directory/count"
        state=disabled
        hung=false
        emit() {
            held=false
            if [ "$state" = active ]; then held=true; fi
            printf '{"reason":"%s","power":"ac","lidClosed":false,"lidControlAccepted":%s,"assertionHeld":%s,"thermal":0}\n' "$state" "$held" "$held"
        }
        trap 'exit 0' TERM INT HUP
        emit
        while IFS= read -r command; do
            printf '%s\n' "$command" >> "$directory/commands.$count"
            case "$command" in
                *'"action":"configure"'*)
                    if [ -f "$directory/always-crash" ]; then exit 42; fi
                    ;;
                *'"action":"start"'*)
                    if [ "$count" = 1 ] && [ -f "$directory/crash-on-start" ]; then exit 42; fi
                    if [ "$count" = 1 ] && [ -f "$directory/hang-on-start" ]; then hung=true; fi
                    state=active
                    ;;
                *'"action":"stop"'*) state=disabled ;;
                *'"action":"quit"'*) exit 0 ;;
            esac
            if [ "$hung" = false ]; then emit; fi
        done
        """#
    }

    private func wait(_ timeout: TimeInterval = 5, until predicate: () -> Bool) throws {
        let end = Date().addingTimeInterval(timeout)
        while !predicate() && Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        #expect(predicate())
        if !predicate() { throw Failure.timeout }
    }

    private enum Failure: Error { case timeout, restore }

    @Test func exitedMonitorResumesOriginalSession() throws {
        let fixture = try Fixture("crash-on-start")
        var restores = 0
        let model = fixture.model(restoreSleep: { restores += 1 })
        defer { model.shutdown() }
        model.connect()
        try wait { model.isReady }
        model.setDuration(60)
        model.start()
        let startedAt = model.startedAt
        let powerMode = model.powerMode
        try wait { fixture.launches == 2 && model.active }
        #expect(model.enabled && model.error == nil)
        #expect(model.startedAt == startedAt && model.duration == 60)
        #expect(model.powerMode == powerMode)
        #expect(restores == 1)
        let commands = try String(contentsOf: fixture.directory.appendingPathComponent("commands.2"), encoding: .utf8)
            .split(separator: "\n").map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
        let resumed = try #require(commands.first { $0["action"] as? String == "start" })
        #expect(try #require(resumed["seconds"] as? Double) < 60)
        let configured = try #require(commands.first { $0["action"] as? String == "configure" })
        #expect(configured["powerMode"] as? String == powerMode.rawValue)
    }

    @Test func stoppingDuringReconnectNeverResumes() throws {
        let fixture = try Fixture("crash-on-start")
        let model = fixture.model()
        defer { model.shutdown() }
        model.connect()
        try wait { model.isReady }
        model.start()
        try wait { model.reconnecting }
        model.stop()
        try wait { fixture.launches == 2 && model.isReady }
        #expect(!model.enabled && !model.active)
        #expect(model.status?.reason == .disabled)
    }

    @Test func reconnectDoesNotExtendExpiredTimer() throws {
        let fixture = try Fixture("crash-on-start")
        let model = fixture.model()
        defer { model.shutdown() }
        model.connect()
        try wait { model.isReady }
        model.setDuration(1)
        model.start()
        let startedAt = model.startedAt
        try wait { fixture.launches == 2 && model.isReady }
        #expect(!model.enabled && !model.active)
        #expect(model.startedAt == startedAt)
    }

    @Test func recoveryIsBoundedAndSwitchCanRetry() throws {
        let fixture = try Fixture("always-crash")
        let model = fixture.model()
        defer { model.shutdown() }
        model.connect()
        try wait(12) { model.error != nil }
        #expect(fixture.launches == 4)
        #expect(!model.enabled && model.canRetry && !model.reconnecting)
        try FileManager.default.removeItem(at: fixture.directory.appendingPathComponent("always-crash"))
        model.start()
        try wait { fixture.launches == 5 && model.active }
        #expect(model.enabled && model.error == nil)
    }

    @Test func replyTimeoutReplacesUnresponsiveMonitor() throws {
        let fixture = try Fixture("hang-on-start")
        let model = fixture.model()
        defer { model.shutdown() }
        model.connect()
        try wait { model.isReady }
        model.start()
        try wait(12) { fixture.launches == 2 && model.active }
        #expect(model.enabled && model.error == nil)
    }

    @Test func wakeResetsWatchdogAndHonorsExpiredTimer() throws {
        let fixture = try Fixture()
        var uptime: TimeInterval = 100
        let model = fixture.model(clock: { uptime })
        defer { model.shutdown() }
        model.connect()
        try wait { model.isReady }
        model.start()
        try wait { model.active }
        model.workspaceWillSleep()
        uptime += 100
        model.tick()
        #expect(!model.reconnecting && model.enabled)
        model.workspaceDidWake()
        model.tick()
        #expect(!model.reconnecting && model.error == nil)
        #expect(fixture.launches == 1)
        model.setDuration(60)
        model.startedAt = Date().addingTimeInterval(-120)
        model.workspaceDidWake()
        try wait { !model.active && model.status?.reason == .disabled }
        #expect(!model.enabled)
    }

    @Test func failedEmergencyRestoreCannotResume() throws {
        let fixture = try Fixture("crash-on-start")
        let model = fixture.model(restoreSleep: { throw Failure.restore })
        defer { model.shutdown() }
        model.connect()
        try wait { model.isReady }
        model.start()
        try wait { model.error != nil }
        #expect(!model.enabled && !model.canRetry && !model.reconnecting)
        #expect(fixture.launches == 1)
    }
}
