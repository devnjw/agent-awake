import Testing
import Foundation
@testable import AgentAwakeCore

@Test func powerAndThermalSafety() {
    var policy = SessionPolicy(now: 100)
    policy.enabled = true
    #expect(policy.reason(now: 101, power: .ac, hot: false, hasLid: true) == .active)
    #expect(policy.reason(now: 101, power: .battery, hot: false, hasLid: true) == .battery)
    #expect(policy.reason(now: 101, power: .unknown, hot: false, hasLid: true) == .unknownPower)
    #expect(policy.reason(now: 101, power: .ac, hot: true, hasLid: true) == .thermal)
    #expect(policy.reason(now: 101, power: .ac, hot: false, hasLid: false) == .unsupported)
}

@Test func batteryModeIsOptInAndReevaluatesWithoutRestarting() {
    var policy = SessionPolicy(now: 100)
    policy.enabled = true
    policy.deadline = 106
    #expect(policy.powerMode == .pluggedInOnly)
    #expect(policy.reason(now: 101, power: .battery, hot: false, hasLid: true) == .battery)
    policy.powerMode = .anyPower
    #expect(policy.reason(now: 102, power: .battery, hot: false, hasLid: true) == .active)
    #expect(policy.reason(now: 102, power: .ac, hot: false, hasLid: true) == .active)
    policy.powerMode = .pluggedInOnly
    #expect(policy.reason(now: 103, power: .battery, hot: false, hasLid: true) == .battery)
    #expect(policy.enabled)
    #expect(policy.deadline == 106)
    policy.powerMode = .anyPower
    #expect(policy.reason(now: 106, power: .battery, hot: false, hasLid: true) == .expired)
}

@Test func batteryModePreservesSafetyAndStopRules() {
    var policy = SessionPolicy(now: 100)
    policy.enabled = true
    policy.powerMode = .anyPower
    #expect(policy.reason(now: 101, power: .battery, hot: true, hasLid: true) == .thermal)
    #expect(policy.reason(now: 101, power: .battery, hot: false, hasLid: false) == .unsupported)
    #expect(policy.reason(now: 101, power: .unknown, hot: false, hasLid: true) == .unknownPower)
    #expect(policy.reason(now: 108, power: .battery, hot: false, hasLid: true) == .disconnected)
    policy.enabled = false
    #expect(policy.reason(now: 101, power: .battery, hot: false, hasLid: true) == .disabled)
}

@Test func guardProtocolSupportsPowerModeAndOlderCommands() throws {
    let decoder = JSONDecoder()
    let old = try decoder.decode(GuardCommand.self, from: Data(#"{"action":"start","seconds":3600}"#.utf8))
    #expect(old.action == "start" && old.seconds == 3600 && old.powerMode == nil)
    let configure = GuardCommand("configure", powerMode: .anyPower)
    let decoded = try decoder.decode(GuardCommand.self, from: JSONEncoder().encode(configure))
    #expect(decoded.action == "configure" && decoded.powerMode == .anyPower && decoded.seconds == nil)
}

@Test func heartbeatAndDeadlineBoundaries() {
    var policy = SessionPolicy(now: 100)
    policy.enabled = true
    #expect(policy.reason(now: 107.99, power: .ac, hot: false, hasLid: true) == .active)
    #expect(policy.reason(now: 108, power: .ac, hot: false, hasLid: true) == .disconnected)
    policy.lastHeartbeat = 110
    policy.deadline = 115
    #expect(policy.reason(now: 114.99, power: .ac, hot: false, hasLid: true) == .active)
    #expect(policy.reason(now: 115, power: .ac, hot: false, hasLid: true) == .expired)
}

@Test func unplugAndReconnectKeepsIntentButNeverHoldsOnBattery() {
    var policy = SessionPolicy(now: 0)
    policy.enabled = true
    for (time, power, expected): (Double, PowerSource, HoldReason) in [
        (1, .ac, .active), (2, .battery, .battery), (3, .ac, .active)
    ] {
        #expect(policy.reason(now: time, power: power, hot: false, hasLid: true) == expected)
    }
    policy.enabled = false
    #expect(policy.reason(now: 4, power: .ac, hot: false, hasLid: true) == .disabled)
}
