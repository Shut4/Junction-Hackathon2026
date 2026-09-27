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
        return hit.stage == .danger ? coreLocalized("止まって。") : coreLocalized("{0}に障害物。",place)
    }
}

/// A subsampled depth frame kept for placing object detections in metres (forward distance and left/right).
public struct DepthGrid: Sendable {
    /// Row-major depth (m) every `step` pixels of the `width`×`height` depth map; NaN where invalid.
    public var values: [Float]; public var columns: Int; public var rows: Int; public var step: Int
    public var fx: Float, fy: Float, cx: Float, cy: Float
    public var gravity: SIMD3<Float>; public var time: Double
    /// Floor height relative to the lens (negative, m) when measured from this frame; used by the ground check.
    public var floor: Float?
    public init(values: [Float], columns: Int, rows: Int, step: Int, fx: Float, fy: Float, cx: Float, cy: Float, gravity: SIMD3<Float>, time: Double, floor: Float? = nil) {
        self.values = values; self.columns = columns; self.rows = rows; self.step = step; self.fx = fx; self.fy = fy; self.cx = cx; self.cy = cy; self.gravity = gravity; self.time = time; self.floor = floor
    }
    /// Valid depths of grid cells whose centre lies in `box` (normalised, upright portrait, origin bottom-left).
    func depths(in box: Box, excluding inner: Box? = nil) -> [Float] {
        let u0 = max(0, Int((1 - box.y - box.height) * Double(columns))), u1 = min(columns - 1, Int((1 - box.y) * Double(columns)))
        let v0 = max(0, Int((1 - box.x - box.width) * Double(rows))), v1 = min(rows - 1, Int((1 - box.x) * Double(rows)))
        guard u0 <= u1, v0 <= v1 else { return [] }
        var out: [Float] = []
        for v in v0...v1 { for u in u0...u1 {
            if let inner {
                let x = 1 - (Double(v) + 0.5) / Double(rows), y = 1 - (Double(u) + 0.5) / Double(columns)
                if x >= inner.x && x <= inner.x + inner.width && y >= inner.y && y <= inner.y + inner.height { continue }
            }
            let z = values[v * columns + u]
            if z.isFinite && z > 0.2 { out.append(z) }
        } }
        return out
    }
    /// Why a detection is implausible for its class, or nil if it looks real (or depth cannot tell).
    /// - Picture check: the box is as far as its surroundings and flat inside — a screen, photo or poster, not an object.
    /// - Ground check: classes that stand on (or are painted on) the ground must have their bottom near the floor.
    public func implausibility(_ box: Box, label: String, config c: DepthCheck) -> String? {
        guard c.enabled else { return nil }
        let inside = depths(in: box)
        guard inside.count >= 6 else { return nil }
        let near = HeadLevelGeometry.percentile(inside, 0.2)
        guard near <= c.maxRange else { return nil }
        if !DepthCheck.flatLabels.contains(label) {
            let pad = 0.3
            let ring = depths(in: Box(x: box.x - box.width * pad, y: box.y - box.height * pad, width: box.width * (1 + 2 * pad), height: box.height * (1 + 2 * pad)), excluding: box)
            if ring.count >= 6 {
                let around = HeadLevelGeometry.percentile(ring, 0.5), spread = HeadLevelGeometry.percentile(inside, 0.8) - near
                if around - near < c.minContrast && spread < c.minContrast { return coreLocalized("平面（画面・写真の可能性）") }
            }
        }
        if DepthCheck.groundLabels.contains(label), box.y > 0.02, let floor, let axes = HeadLevelGeometry.axes(gravity: gravity) {
            // Bottom edge centre: where the object meets the ground.
            let u = Int((1 - box.y - box.height * 0.05) * Double(columns)), v = Int((1 - box.x - box.width / 2) * Double(rows))
            var zs: [Float] = []
            for dv in -1...1 { for du in -1...1 {
                let uu = u + du, vv = v + dv
                guard uu >= 0, uu < columns, vv >= 0, vv < rows else { continue }
                let z = values[vv * columns + uu]; if z.isFinite && z > 0.2 { zs.append(z) }
            } }
            if zs.count >= 3 {
                let p = HeadLevelGeometry.devicePoint(u: Float(u * step), v: Float(v * step), depth: zs.sorted()[zs.count / 2], fx: fx, fy: fy, cx: cx, cy: cy)
                if simd_dot(p, axes.up) - floor > c.groundTolerance { return coreLocalized("床から浮いている") }
            }
        }
        return nil
    }
}

/// DeveloperMode tuning of the depth plausibility check that removes false detections.
public struct DepthCheck: Sendable, Codable, Equatable {
    public var enabled = true
    /// Object must be nearer than its surroundings by this much (m), unless flat by nature.
    public var minContrast: Float = 0.15
    /// Ground classes: bottom edge at most this far above the floor (m).
    public var groundTolerance: Float = 0.4
    /// Beyond this distance (m) depth is too coarse to judge; detections are kept.
    public var maxRange: Float = 5
    public init() {}
    /// Painted or sheet-like classes: no picture check.
    public static let flatLabels: Set<String> = ["braille_block", "crosswalk", "white_line", "signboard", "flag"]
    /// Classes standing on or painted on the ground: ground check.
    public static let groundLabels: Set<String> = ["steps", "stairs", "pole", "bollard", "safety-cone", "braille_block", "crosswalk", "white_line", "bicycle", "bicycler", "motorbike"]
}

extension DepthGrid {
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
