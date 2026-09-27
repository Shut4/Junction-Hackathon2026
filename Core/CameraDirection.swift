import Foundation
/// Coarse direction of the route relative to the device, used for the camera arrow's spoken guidance.
public enum DirectionBucket: String, Sendable, CaseIterable {
    case ahead, slightRight, right, behind, left, slightLeft
    /// Lower edge (absolute degrees) of each side bucket; `ahead` is below the first.
    static let edges = (slight: 20.0, turn: 60.0, behind: 150.0)
    public static func of(_ angle: Double) -> DirectionBucket {
        let a = abs(angle)
        if a < edges.slight { return .ahead }
        if a >= edges.behind { return .behind }
        if a < edges.turn { return angle > 0 ? .slightRight : .slightLeft }
        return angle > 0 ? .right : .left
    }
    /// Keeps `current` until the angle is `margin` degrees past its boundary, so noise near an edge does not flip-flop.
    public static func of(_ angle: Double, keeping current: DirectionBucket?, margin: Double = 8) -> DirectionBucket {
        let raw = of(angle)
        guard let current, raw != current else { return raw }
        let nudged = [angle - margin, angle + margin].map { of($0) }
        return nudged.contains(current) ? current : raw
    }
    public func phrase(degrees: Int) -> String {
        switch self {
        case .ahead: return coreLocalized("正面方向です。そのまま進んでください。")
        case .slightRight: return coreLocalized("やや右方向です。")
        case .slightLeft: return coreLocalized("やや左方向です。")
        case .right: return coreLocalized("右へ約{0}度、向きを変えてください。",degrees)
        case .left: return coreLocalized("左へ約{0}度、向きを変えてください。",degrees)
        case .behind: return coreLocalized("後ろ方向です。向きを変えてください。")
        }
    }
}

/// Decides when to speak the camera arrow direction: after the bucket has been stable, with a minimum gap,
/// repeating a turn request while the user has not yet faced the route, and saying once when the arrow is held.
public struct DirectionAnnouncer: Sendable {
    public var stability = 1.2; public var gap = 4.0; public var repeatTurn = 10.0; public var holdDelay = 3.0
    private var candidate: DirectionBucket?; private var candidateSince = 0.0
    private var spoken: DirectionBucket?; private var lastSpoke = -Double.infinity
    private var unavailableSince: Double?; private var heldSpoken = false
    public init() {}
    public mutating func reset() { candidate=nil;spoken=nil;lastSpoke = -.infinity;unavailableSince=nil;heldSpoken=false }
    /// `angle` is nil while the arrow is withheld; `reason` is then spoken once after `holdDelay`.
    public mutating func update(angle: Double?, reason: String, now: Double) -> String? {
        guard let angle else {
            if unavailableSince == nil { unavailableSince = now }
            candidate = nil
            if !heldSpoken, now - unavailableSince! >= holdDelay { heldSpoken = true; spoken = nil; lastSpoke = now; return reason }
            return nil
        }
        unavailableSince = nil; heldSpoken = false
        let bucket = DirectionBucket.of(angle, keeping: candidate)
        if bucket != candidate { candidate = bucket; candidateSince = now }
        guard now - candidateSince >= stability, now - lastSpoke >= gap else { return nil }
        let turning = bucket != .ahead && bucket != .slightLeft && bucket != .slightRight
        guard bucket != spoken || (turning && now - lastSpoke >= repeatTurn) else { return nil }
        spoken = bucket; lastSpoke = now
        return bucket.phrase(degrees: Int((abs(angle) / 5).rounded() * 5))
    }
}

/// Rear-camera tilt below the horizon and roll about the lens axis, from gravity in device coordinates (portrait, unit g).
public enum CameraPose {
    public static func from(gravityX x: Double, y: Double, z: Double) -> (tilt: Double, roll: Double) {
        (asin(max(-1, min(1, -z))), atan2(-x, -y))
    }
}
