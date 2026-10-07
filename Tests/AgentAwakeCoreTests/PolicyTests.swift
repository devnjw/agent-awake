import Testing
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
