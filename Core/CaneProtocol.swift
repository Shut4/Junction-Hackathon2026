import Foundation

public enum CaneState: UInt8, Sendable, CaseIterable {
    case clear = 0, caution = 1, danger = 2, unavailable = 3
    public var title: String { switch self { case .clear: "検出なし"; case .caution: "注意"; case .danger: "危険"; case .unavailable: "検知不能" } }
}

/// CaneVibe protocol v1. Multibyte fields are little endian; TTL is always 1000 ms.
public struct CaneCommand: Sendable, Equatable {
    public var state: CaneState
    public var distance: UInt16
    public var floorMeasured: Bool
    public var manual: Bool
    public init(state: CaneState = .unavailable, distance: UInt16 = .max, floorMeasured: Bool = false, manual: Bool = false) {
        self.state=state;self.distance=distance;self.floorMeasured=floorMeasured;self.manual=manual
    }
    public func data(sequence: UInt16) -> Data {
        let d = state == .clear || state == .unavailable ? UInt16.max : distance
        return Data([1,state.rawValue,UInt8(truncatingIfNeeded:sequence),UInt8(sequence >> 8),0xE8,3,
                     UInt8(truncatingIfNeeded:d),UInt8(d >> 8),(floorMeasured ? 1:0) | (manual ? 2:0),0])
    }
}

public struct CaneStatus: Sendable, Equatable {
    public let state: CaneState
    public let errors: UInt8
    public let gpioHigh: Bool
    public let sequence: UInt16
    public let uptime: UInt32
    public init?(data: Data) {
        let b=Array(data)
        guard b.count == 10,b[0] == 1,let state=CaneState(rawValue:b[1]),b[2] & 0xFC == 0,b[3] <= 1 else { return nil }
        self.state=state;errors=b[2];gpioHigh=b[3] == 1
        sequence=UInt16(b[4]) | UInt16(b[5]) << 8
        uptime=UInt32(b[6]) | UInt32(b[7]) << 8 | UInt32(b[8]) << 16 | UInt32(b[9]) << 24
    }
}

/// Counts depth frames, never heartbeat sends. Stale/invalid input immediately clears continuity.
public struct CaneDetectionState: Sendable {
    private var candidate: CaneState = .unavailable
    private var count=0
    private var lastTime = -Double.infinity
    private var command=CaneCommand()
    public init() {}
    public mutating func reset() { self=Self() }
    public mutating func update(state: CaneState, distance: Float?, floorMeasured: Bool, capturedAt: Double, now: Double) {
        guard state != .unavailable,capturedAt.isFinite,now >= capturedAt,now-capturedAt <= 0.6,capturedAt > lastTime else { reset();return }
        if capturedAt-lastTime > 0.6 { reset() }
        lastTime=capturedAt
        if candidate == state { count += 1 } else { candidate=state;count=1 }
        guard count >= 2 else { return }
        let mm: UInt16 = distance.flatMap { $0.isFinite && $0 >= 0 ? UInt16(min(65534,(Double($0)*1000).rounded())):nil } ?? .max
        command=CaneCommand(state:state,distance:mm,floorMeasured:floorMeasured)
    }
    public mutating func current(now: Double, enabled: Bool) -> CaneCommand {
        guard enabled,now-lastTime >= 0,now-lastTime <= 0.6 else { reset();return CaneCommand() }
        return command
    }
}
