import Foundation
import simd

/// Obstacles at chest/head height in the walking corridor, which a white cane sweeping the ground does not reach.
/// Input is depth points in the device frame (portrait: x right, y up, rear camera looks along -z) plus gravity.
public struct HeadLevelConfig: Sendable, Codable, Equatable {
    public var corridorHalfWidth: Float = 0.45
    public var minDistance: Float = 0.3
    public var maxDistance: Float = 2.0
    public var minHeight: Float = 1.0
    public var maxHeight: Float = 2.0
    public var dangerDistance: Float = 1.0
    /// Hits needed in one frame so isolated depth noise is ignored.
    public var minPoints = 12
    public init() {}
}
public enum HeadLevelStage: Int, Sendable, Comparable {
    case caution = 1, danger = 2
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}
public struct HeadLevelHit: Sendable, Equatable {
    /// Forward distance (m), signed lateral offset (m, positive = right), height above the floor (m).
    public var distance: Float; public var lateral: Float; public var height: Float; public var count: Int; public var stage: HeadLevelStage
}
public struct HeadLevelResult: Sendable {
    /// Floor height relative to the lens (negative, m) and whether it was measured rather than assumed.
    public var floor: Float; public var floorMeasured: Bool; public var hit: HeadLevelHit?
}

public enum HeadLevelGeometry {
    /// Device-frame point for a depth pixel. The buffer is the sensor's landscape image that is shown rotated `.right`
    /// in portrait: buffer columns (u) run down the screen, buffer rows (v) run from right to left.
    public static func devicePoint(u: Float, v: Float, depth z: Float, fx: Float, fy: Float, cx: Float, cy: Float) -> SIMD3<Float> {
        SIMD3(-(v - cy) * z / fy, -(u - cx) * z / fx, -z)
    }
    public static func evaluate(points: [SIMD3<Float>], gravity: SIMD3<Float>, cameraHeight: Float, config: HeadLevelConfig = HeadLevelConfig()) -> HeadLevelResult {
        let assumed = HeadLevelResult(floor: -cameraHeight, floorMeasured: false, hit: nil)
        guard simd_length(gravity) > 0.1 else { return assumed }
        let up = -simd_normalize(gravity)
        let lens = SIMD3<Float>(0, 0, -1)
        let flat = lens - up * simd_dot(lens, up)
        // Looking almost straight up or down: no usable forward direction.
        guard simd_length(flat) > 0.2 else { return assumed }
        let forward = simd_normalize(flat), right = simd_cross(forward, up)
        var ground: [Float] = [], hits: [(d: Float, l: Float, h: Float)] = []
        for p in points {
            let h = simd_dot(p, up), d = simd_dot(p, forward), l = simd_dot(p, right)
            if d > 0.5 && d < 4 && abs(l) < 1.5 && h < -0.3 { ground.append(h) }
            if d >= config.minDistance && d <= config.maxDistance && abs(l) <= config.corridorHalfWidth { hits.append((d, l, h)) }
        }
        // Floor: a low percentile of points ahead, if plausible for a chest/neck-worn phone; otherwise the configured height.
        var floor = -cameraHeight, measured = false
        if ground.count >= 30 {
            let candidate = percentile(ground, 0.1)
            if candidate > -1.9 && candidate < -0.5 { floor = candidate; measured = true }
        }
        let high = hits.filter { $0.h - floor >= config.minHeight && $0.h - floor <= config.maxHeight }
        guard high.count >= config.minPoints else { return HeadLevelResult(floor: floor, floorMeasured: measured, hit: nil) }
        let distance = percentile(high.map(\.d), 0.2)
        let hit = HeadLevelHit(distance: distance, lateral: percentile(high.map(\.l), 0.5), height: percentile(high.map { $0.h - floor }, 0.5), count: high.count,
                               stage: distance <= config.dangerDistance ? .danger : .caution)
        return HeadLevelResult(floor: floor, floorMeasured: measured, hit: hit)
    }
    static func percentile(_ values: [Float], _ q: Float) -> Float {
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, max(0, Int(Float(sorted.count - 1) * q)))]
    }
}

/// Turns per-frame hits into spoken warnings: needs consecutive frames, speaks escalations at once, otherwise repeats after `timing.cooldown`.
/// Timing of spoken head-level warnings; tunable from DeveloperMode.
public struct HeadLevelTiming: Sendable, Codable, Equatable {
    public var persistence = 2; public var cooldown = 5.0; public var clearAfter = 1.0
    public init() {}
}
public struct HeadLevelAnnouncer: Sendable {
    public var timing = HeadLevelTiming()
    private var streak = 0; private var lastStage: HeadLevelStage?; private var lastSpoke = -Double.infinity; private var lastSeen = -Double.infinity
    public init(timing: HeadLevelTiming = HeadLevelTiming()) { self.timing = timing }
    public mutating func reset() { streak = 0; lastStage = nil; lastSpoke = -.infinity; lastSeen = -.infinity }
    public mutating func update(_ hit: HeadLevelHit?, now: Double) -> (stage: HeadLevelStage, text: String)? {
        guard let hit else {
            streak = 0
            if now - lastSeen >= timing.clearAfter { lastStage = nil }
            return nil
        }
        streak += 1; lastSeen = now
        guard streak >= timing.persistence else { return nil }
        let escalated = lastStage.map { hit.stage > $0 } ?? true
        guard escalated || now - lastSpoke >= timing.cooldown else { return nil }
        lastStage = hit.stage; lastSpoke = now
        return (hit.stage, Self.text(hit))
    }
    public static func text(_ hit: HeadLevelHit) -> String {
        let side = hit.lateral > 0.15 ? "右寄り" : hit.lateral < -0.15 ? "左寄り" : "正面"
        let meters = (hit.distance * 2).rounded() / 2
        let distance = hit.distance < 1 ? "すぐ近く" : "約\(meters.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(meters)) : String(format: "%.1f", meters))メートル"
        return hit.stage == .danger ? "止まってください。頭の高さ、\(side)\(distance)に障害物。" : "頭の高さ、\(side)\(distance)に障害物があります。"
    }
}
