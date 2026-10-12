import Foundation
import Testing
@testable import AgentAwake

struct BuiltInDisplayBrightnessTests {
    private enum Failure: Error { case read, write }
    private final class Fixture {
        var ids: [UInt32] = [1]
        var levels: [UInt32: Float] = [1: 0.65, 2: 0.8]
        var writes: [(UInt32, Float)] = []
        var failRead = false
        var failWrite = false
        lazy var controller = BuiltInDisplayBrightness(displays: { self.ids }, read: { id in
            if self.failRead { throw Failure.read }
            return self.levels[id]!
        }, write: { id, level in
            self.writes.append((id, level))
            if self.failWrite { throw Failure.write }
            self.levels[id] = level
        })
    }

    @Test func closureDimsOnceAndOpeningRestoresOnlyTheBuiltInDisplay() throws {
        let f = Fixture()
        try f.controller.update(active: true, lidClosed: false)
        #expect(f.writes.isEmpty)
        try f.controller.update(active: true, lidClosed: true)
        #expect(f.levels[1] == 0)
        #expect(f.levels[2] == 0.8)
        try f.controller.update(active: true, lidClosed: true)
        try f.controller.update(active: true, lidClosed: nil)
        #expect(f.writes.count == 1)
        try f.controller.update(active: true, lidClosed: false)
        #expect(f.levels[1] == 0.65)
        // Capture the user's new brightness on the next closure.
        f.levels[1] = 0.4
        try f.controller.update(active: true, lidClosed: false)
        try f.controller.update(active: true, lidClosed: true)
        try f.controller.restore()
        #expect(f.levels[1] == 0.4)
        #expect(f.levels[2] == 0.8)
    }

    @Test func inactiveAndUnknownLidDoNotDimButPauseRestores() throws {
        let f = Fixture()
        try f.controller.update(active: false, lidClosed: true)
        try f.controller.update(active: true, lidClosed: nil)
        #expect(f.writes.isEmpty)
        try f.controller.update(active: true, lidClosed: true)
        try f.controller.update(active: false, lidClosed: nil)
        #expect(f.levels[1] == 0.65)
        try f.controller.restore()
        #expect(f.writes.count == 2)
    }

    @Test func remembersOpenBrightnessWhenClosedDisplayReadsZero() throws {
        let f = Fixture()
        try f.controller.update(active: true, lidClosed: false)
        f.levels[1] = 0
        try f.controller.update(active: true, lidClosed: true)
        try f.controller.update(active: true, lidClosed: false)
        #expect(f.levels[1] == 0.65)
    }

    @Test func clamshellWithoutAnOnlineBuiltInDisplayDoesNotBlockControls() throws {
        let f = Fixture()
        f.ids = []
        try f.controller.update(active: true, lidClosed: true)
        #expect(f.writes.isEmpty)
    }

    @Test func failedReadNeverChangesBrightnessAndCanRetry() throws {
        let f = Fixture()
        f.failRead = true
        #expect(throws: Failure.read) { try f.controller.update(active: true, lidClosed: true) }
        #expect(f.writes.isEmpty)
        f.failRead = false
        try f.controller.update(active: true, lidClosed: true)
        try f.controller.restore()
        #expect(f.levels[1] == 0.65)
    }

    @Test func failedDimAndRestoreRetainOriginalForRetry() throws {
        let f = Fixture()
        f.failWrite = true
        #expect(throws: Failure.write) { try f.controller.update(active: true, lidClosed: true) }
        f.failWrite = false
        try f.controller.update(active: true, lidClosed: true)
        f.failWrite = true
        #expect(throws: Failure.write) { try f.controller.restore() }
        #expect(f.levels[1] == 0)
        f.failWrite = false
        try f.controller.restore()
        #expect(f.levels[1] == 0.65)
    }
}
