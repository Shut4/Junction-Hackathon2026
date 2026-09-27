import Foundation
import simd

/// Obstacles at chest/head height in the walking corridor, which a white cane sweeping the ground does not reach.
/// Input is depth points in the device frame (portrait: x right, y up, rear camera looks along -z) plus gravity.
public struct HeadLevelConfig: Sendable, Codable, Equatable {
    public var corridorHalfWidth: Float = 0.45
    public var minDistance: Float = 0.3
    public var maxDistance: Float = 2.5
    public var minHeight: Float = 1.0
    public var maxHeight: Float = 2.0
    public var dangerDistance: Float = 2.0
    /// Within this distance (m) a continuous buzzer sounds until the obstacle is gone (0 = off).
    public var buzzerDistance: Float = 1.0
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
    /// Walkable ground around the walker from the same depth frame (nil when the frame has no usable orientation).
    public var walkable: WalkableProfile? = nil
}

public enum HeadLevelGeometry {
    /// Device-frame point for a depth pixel. The buffer is the sensor's landscape image that is shown rotated `.right`
    /// in portrait: buffer columns (u) run down the screen, buffer rows (v) run from right to left.
    public static func devicePoint(u: Float, v: Float, depth z: Float, fx: Float, fy: Float, cx: Float, cy: Float) -> SIMD3<Float> {
        SIMD3(-(v - cy) * z / fy, -(u - cx) * z / fx, -z)
    }
    /// Gravity-aligned walker axes in the device frame: up, horizontal forward (lens direction) and right.
    /// Nil when gravity is unknown or the phone looks almost straight up or down.
    public static func axes(gravity: SIMD3<Float>) -> (up: SIMD3<Float>, forward: SIMD3<Float>, right: SIMD3<Float>)? {
        guard simd_length(gravity) > 0.1 else { return nil }
        let up = -simd_normalize(gravity)
        let lens = SIMD3<Float>(0, 0, -1)
        let flat = lens - up * simd_dot(lens, up)
        guard simd_length(flat) > 0.2 else { return nil }
        let forward = simd_normalize(flat)
        return (up, forward, simd_cross(forward, up))
    }
    public static func evaluate(points: [SIMD3<Float>], gravity: SIMD3<Float>, cameraHeight: Float, config: HeadLevelConfig = HeadLevelConfig(), walkable walkConfig: WalkableConfig = WalkableConfig()) -> HeadLevelResult {
        let assumed = HeadLevelResult(floor: -cameraHeight, floorMeasured: false, hit: nil)
        guard let (up, forward, right) = axes(gravity: gravity) else { return assumed }
        var ground: [Float] = [], hits: [(d: Float, l: Float, h: Float)] = [], around: [WalkSample] = []
        for p in points {
            let h = simd_dot(p, up), d = simd_dot(p, forward), l = simd_dot(p, right)
            if d > 0.5 && d < 4 && abs(l) < 1.5 && h < -0.3 { ground.append(h) }
            if d >= config.minDistance && d <= config.maxDistance && abs(l) <= config.corridorHalfWidth { hits.append((d, l, h)) }
            if d >= walkConfig.nearest && d <= walkConfig.farthest && abs(l) <= walkConfig.halfWidth { around.append(WalkSample(forward: d, lateral: l, up: h)) }
        }
        // Floor: a low percentile of points ahead, if plausible for a chest/neck-worn phone; otherwise the configured height.
        var floor = -cameraHeight, measured = false
        if ground.count >= 30 {
            let candidate = percentile(ground, 0.1)
            if candidate > -1.9 && candidate < -0.5 { floor = candidate; measured = true }
        }
        let walkable = WalkableGeometry.profile(around, floor: floor, config: walkConfig)
        let high = hits.filter { $0.h - floor >= config.minHeight && $0.h - floor <= config.maxHeight }
        guard high.count >= config.minPoints else { return HeadLevelResult(floor: floor, floorMeasured: measured, hit: nil, walkable: walkable) }
        let distance = percentile(high.map(\.d), 0.2)
        let hit = HeadLevelHit(distance: distance, lateral: percentile(high.map(\.l), 0.5), height: percentile(high.map { $0.h - floor }, 0.5), count: high.count,
                               stage: distance <= config.dangerDistance ? .danger : .caution)
        return HeadLevelResult(floor: floor, floorMeasured: measured, hit: hit, walkable: walkable)
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
        // Short, no metres: closeness is carried by the stage (vibration and colour).
        let side = hit.lateral > 0.15 ? "右" : hit.lateral < -0.15 ? "左" : "正面"
        let place = NoticeFilter.position(side: side, close: hit.stage == .danger)
        return hit.stage == .danger ? "止まって。" : "\(place)に障害物。"
    }
}

/// A subsampled depth frame kept for placing object detections in metres (forward distance and left/right).
public struct DepthGrid: Sendable {
    /// Row-major depth (m) every `step` pixels of the `width`×`height` depth map; NaN where invalid.
    public var values: [Float]; public var columns: Int; public var rows: Int; public var step: Int
    public var fx: Float, fy: Float, cx: Float, cy: Float
    public var gravity: SIMD3<Float>; public var time: Double
    public init(values: [Float], columns: Int, rows: Int, step: Int, fx: Float, fy: Float, cx: Float, cy: Float, gravity: SIMD3<Float>, time: Double) {
        self.values = values; self.columns = columns; self.rows = rows; self.step = step; self.fx = fx; self.fy = fy; self.cx = cx; self.cy = cy; self.gravity = gravity; self.time = time
    }
    /// Forward distance and lateral offset of a Vision box (normalised, upright portrait, origin bottom-left),
    /// sampled a little above its bottom edge (where most objects meet the ground) with a 3×3 median.
    public func locate(_ box: Box) -> (distance: Double, lateral: Double)? {
        guard let axes = HeadLevelGeometry.axes(gravity: gravity) else { return nil }
        // Upright portrait ↔ landscape buffer: columns run down the screen, rows run right to left.
        let x = box.x + box.width / 2, y = box.y + box.height * 0.2
        let gu = Int((1 - y) * Double(columns)), gv = Int((1 - x) * Double(rows))
        var found: [Float] = []
        for dv in -1...1 { for du in -1...1 {
            let u = gu + du, v = gv + dv
            guard u >= 0, u < columns, v >= 0, v < rows else { continue }
            let z = values[v * columns + u]
            if z.isFinite && z > 0.2 { found.append(z) }
        } }
        guard found.count >= 3 else { return nil }
        let z = found.sorted()[found.count / 2]
        let p = HeadLevelGeometry.devicePoint(u: Float(gu * step), v: Float(gv * step), depth: z, fx: fx, fy: fy, cx: cx, cy: cy)
        return (Double(simd_dot(p, axes.forward)), Double(simd_dot(p, axes.right)))
    }
}
