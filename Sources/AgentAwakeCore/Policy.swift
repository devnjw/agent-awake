import Foundation

public enum PowerSource: String, Codable, Sendable {
    case ac, battery, unknown
}

public enum HoldReason: String, Codable, Sendable {
    case active, disabled, battery, unknownPower, thermal, expired, disconnected, unsupported, error
}

public struct SessionPolicy: Sendable {
    public var enabled = false
    public var deadline: TimeInterval?
    public var lastHeartbeat: TimeInterval
    public let heartbeatTimeout: TimeInterval = 8

    public init(now: TimeInterval) { lastHeartbeat = now }

    public func reason(now: TimeInterval, power: PowerSource, hot: Bool, hasLid: Bool) -> HoldReason {
        if now - lastHeartbeat >= heartbeatTimeout { return .disconnected }
        if !enabled { return .disabled }
        if let deadline, now >= deadline { return .expired }
        if !hasLid { return .unsupported }
        if hot { return .thermal }
        switch power {
        case .ac: return .active
        case .battery: return .battery
        case .unknown: return .unknownPower
        }
    }
}

public struct GuardCommand: Codable, Sendable {
    public var action: String
    public var seconds: TimeInterval?
    public init(_ action: String, seconds: TimeInterval? = nil) {
        self.action = action
        self.seconds = seconds
    }
}

public struct GuardStatus: Codable, Equatable, Sendable {
    public var reason: HoldReason
    public var power: PowerSource
    public var battery: Int?
    public var lidClosed: Bool?
    public var lidControlAccepted: Bool
    public var assertionHeld: Bool
    public var thermal: Int
    public var message: String?

    public init(reason: HoldReason, power: PowerSource, battery: Int?, lidClosed: Bool?,
                lidControlAccepted: Bool, assertionHeld: Bool, thermal: Int, message: String? = nil) {
        self.reason = reason; self.power = power; self.battery = battery
        self.lidClosed = lidClosed; self.lidControlAccepted = lidControlAccepted
        self.assertionHeld = assertionHeld; self.thermal = thermal; self.message = message
    }
    public var active: Bool { reason == .active && assertionHeld && lidControlAccepted }
}
