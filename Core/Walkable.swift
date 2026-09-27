import Foundation

/// "Where can I walk" from camera depth, without a segmentation model: depth points around the walker are sorted into
/// 10 cm lateral strips, and each strip is marked as ground, obstacle (above the floor) or drop (below the floor).
public struct WalkSample: Sendable { public var forward: Float; public var lateral: Float; public var up: Float
    public init(forward: Float, lateral: Float, up: Float) { self.forward = forward; self.lateral = lateral; self.up = up }
}
public struct WalkableConfig: Sendable, Codable, Equatable {
    public var nearest: Float = 0.5, farthest: Float = 3.0, halfWidth: Float = 1.5, strip: Float = 0.1
    /// Above the floor by this much = obstacle (kerb-high and up); below by `dropHeight` = step down or kerb edge.
    public var obstacleHeight: Float = 0.15, obstacleTop: Float = 2.0, groundTolerance: Float = 0.08, dropHeight: Float = 0.12
    public var minPoints = 3
    /// Half width of the walker's own path, the free width needed to pass, "narrow" width and "too close to an edge".
    public var corridorHalf: Float = 0.3, passWidth: Float = 0.6, narrowWidth: Float = 0.8, edgeNear: Float = 0.35
    public init() {}
}
public enum WalkSide: String, Sendable { case left, right
    public var japanese: String { self == .left ? "左" : "右" }
    public var opposite: WalkSide { self == .left ? .right : .left }
}
public struct SideEdge: Sendable, Equatable {
    public enum Kind: Sendable { case obstacle, drop }
    /// Lateral distance (m) from the walker's centre line to the nearest blocked strip on that side.
    public var distance: Float; public var kind: Kind
}
public struct WalkableProfile: Sendable, Equatable {
    /// Distance to something blocking the walker's own path, or to a step down in it.
    public var blockedAhead: Float?; public var dropAhead: Float?
    public var left: SideEdge?; public var right: SideEdge?
    /// When blocked ahead: a side with at least `passWidth` of seen, unobstructed ground next to the path.
    public var passSide: WalkSide?
    /// Free width between the nearest edges, when both are seen.
    public var width: Float? { guard let left, let right else { return nil }; return left.distance + right.distance }
    public var groundSeen: Bool
    public func edge(_ side: WalkSide) -> SideEdge? { side == .left ? left : right }
}

public enum WalkableGeometry {
    private enum Strip { case unknown, ground, obstacle, drop }
    public static func profile(_ samples: [WalkSample], floor: Float, config c: WalkableConfig = WalkableConfig()) -> WalkableProfile {
        let count = Int((2 * c.halfWidth / c.strip).rounded())
        var obstacle = [Int](repeating: 0, count: count), ground = obstacle, drop = obstacle
        var obstacleNear = [Float](repeating: .infinity, count: count), dropNear = obstacleNear
        for s in samples {
            let i = min(count - 1, max(0, Int((s.lateral + c.halfWidth) / c.strip)))
            let h = s.up - floor
            if h >= c.obstacleHeight && h <= c.obstacleTop { obstacle[i] += 1; obstacleNear[i] = min(obstacleNear[i], s.forward) }
            else if abs(h) <= c.groundTolerance { ground[i] += 1 }
            else if h <= -c.dropHeight { drop[i] += 1; dropNear[i] = min(dropNear[i], s.forward) }
        }
        let strips: [Strip] = (0..<count).map { i in
            obstacle[i] >= c.minPoints ? .obstacle : drop[i] >= c.minPoints ? .drop : ground[i] >= c.minPoints ? .ground : .unknown
        }
        func centre(_ i: Int) -> Float { -c.halfWidth + (Float(i) + 0.5) * c.strip }
        let path = (0..<count).filter { abs(centre($0)) <= c.corridorHalf }
        let blocked = path.filter { strips[$0] == .obstacle }.map { obstacleNear[$0] }.min()
        let dropAhead = path.filter { strips[$0] == .drop }.map { dropNear[$0] }.min()
        // Side edges: nearest obstacle/drop strip outside the walker's own path (the path itself is `blockedAhead`).
        func edge(_ side: WalkSide) -> SideEdge? {
            let order = (0..<count).filter { side == .left ? centre($0) < -c.corridorHalf : centre($0) > c.corridorHalf }.sorted { abs(centre($0)) < abs(centre($1)) }
            guard let i = order.first(where: { strips[$0] == .obstacle || strips[$0] == .drop }) else { return nil }
            return SideEdge(distance: abs(centre(i)) - c.strip / 2, kind: strips[i] == .obstacle ? .obstacle : .drop)
        }
        // Passable side: the band just outside the path is clear and mostly seen as ground.
        func passable(_ side: WalkSide) -> Bool {
            let band = (0..<count).filter { let x = side == .left ? -centre($0) : centre($0); return x > c.corridorHalf && x <= c.corridorHalf + c.passWidth }
            return !band.isEmpty && !band.contains { strips[$0] == .obstacle || strips[$0] == .drop } && band.filter { strips[$0] == .ground }.count * 2 >= band.count
        }
        let left = edge(.left), right = edge(.right)
        var pass: WalkSide?
        if blocked != nil {
            let options = [WalkSide.left, .right].filter(passable)
            pass = options.max { (($0 == .left ? left : right)?.distance ?? .infinity) < (($1 == .left ? left : right)?.distance ?? .infinity) }
        }
        return WalkableProfile(blockedAhead: blocked, dropAhead: dropAhead, left: left, right: right, passSide: pass, groundSeen: strips.contains(.ground))
    }
}

/// Spoken cues from successive walkable profiles: at most one per frame, most urgent first, each kind after two frames,
/// repeated per priority (critical 3 s, high 6 s, normal 12 s).
/// DeveloperMode tuning of walkable cues: when they fire, when they become critical and how often they repeat.
public struct WalkableTiming: Sendable, Codable, Equatable {
    public var blockedDistance: Float = 3.0, criticalDistance: Float = 1.8, dropDistance: Float = 3.0
    public var persistence = 2
    public var repeatCritical = 3.0, repeatHigh = 6.0, repeatNormal = 12.0
    public init() {}
}
public struct WalkableAnnouncer: Sendable {
    public var config = WalkableConfig()
    public var timing = WalkableTiming()
    private var repeatAfter: [SpeechPriority: Double] { [.critical: timing.repeatCritical, .high: timing.repeatHigh, .normal: timing.repeatNormal, .low: 30] }
    private var streak: [String: Int] = [:], lastSpoke: [String: Double] = [:]
    public init(config: WalkableConfig = WalkableConfig(), timing: WalkableTiming = WalkableTiming()) { self.config = config; self.timing = timing }
    public mutating func reset() { streak.removeAll(); lastSpoke.removeAll() }
    /// Candidate cues for one profile, most urgent first. `headLevel` suppresses the generic "blocked" cue when the
    /// more specific head-height warning covers the same obstacle.
    public func cues(_ p: WalkableProfile, headLevel: Bool = false) -> [(key: String, priority: SpeechPriority, text: String)] {
        var out: [(String, SpeechPriority, String)] = []
        if let d = p.blockedAhead, d <= timing.blockedDistance, !headLevel {
            let way = p.passSide.map { "\($0.japanese)へ。" } ?? "止まってください。"
            out.append(("blocked", d <= timing.criticalDistance ? .critical : .high, "\(place(d))に障害物。" + way))
        }
        if let d = p.dropAhead, d <= timing.dropDistance { out.append(("drop", d <= timing.criticalDistance ? .critical : .high, "\(place(d))に段差。")) }
        for side in [WalkSide.left, .right] {
            guard let e = p.edge(side), e.distance <= config.edgeNear else { continue }
            if e.kind == .drop { out.append(("edgeDrop-\(side.rawValue)", .high, "\(side.japanese)に段差。\(side.opposite.japanese)へ。")) }
            else { out.append(("edge-\(side.rawValue)", .normal, "少し\(side.opposite.japanese)へ。")) }
        }
        if p.blockedAhead == nil, let w = p.width, w < config.narrowWidth { out.append(("narrow", .normal, "道が狭いです。")) }
        return out.enumerated().sorted { $0.element.1 == $1.element.1 ? $0.offset < $1.offset : $0.element.1 > $1.element.1 }.map { ($0.element.0, $0.element.1, $0.element.2) }
    }
    public mutating func update(_ p: WalkableProfile?, headLevel: Bool = false, now: Double) -> (priority: SpeechPriority, text: String)? {
        let current = p.map { cues($0, headLevel: headLevel) } ?? []
        let keys = Set(current.map(\.key))
        for k in streak.keys where !keys.contains(k) { streak[k] = nil }
        for c in current { streak[c.key, default: 0] += 1 }
        for c in current where streak[c.key, default: 0] >= timing.persistence && now - lastSpoke[c.key, default: -.infinity] >= repeatAfter[c.priority, default: 10] {
            lastSpoke[c.key] = now
            return (c.priority, c.text)
        }
        return nil
    }
    /// 「目の前」 within `timing.criticalDistance`, else 「前方」. No metres are spoken.
    func place(_ d: Float) -> String { d <= timing.criticalDistance ? "目の前" : "前方" }
}

/// One line of the on-screen "surroundings" list, most useful first.
public struct SceneItem: Sendable, Equatable { public var priority: SpeechPriority; public var text: String; public var distance: Double? }
public enum SceneSummary {
    /// Head-level warning, walkable cues and detected objects (one per class, the nearest), ordered by priority then distance.
    public static func items(detections: [Detection], walkable: WalkableProfile?, headLevel: HeadLevelHit?, minConfidence: Double = 0.5, limit: Int = 6,
                             announcer: WalkableAnnouncer = WalkableAnnouncer(), closeDistance: Double = NoticeFilter.closeDistance, announceDistance: Double = 3.0, tiers: [String: SceneTier] = [:]) -> [SceneItem] {
        var items: [SceneItem] = []
        if let h = headLevel { items.append(SceneItem(priority: h.stage == .danger ? .critical : .high, text: HeadLevelAnnouncer.text(h), distance: Double(h.distance))) }
        if let w = walkable {
            items += announcer.cues(w, headLevel: headLevel != nil).map { SceneItem(priority: $0.priority, text: $0.text, distance: nil) }
            if w.blockedAhead == nil && w.dropAhead == nil && w.groundSeen {
                items.append(SceneItem(priority: .low, text: "前方は歩けます。", distance: nil))
            }
        }
        var nearest: [String: Detection] = [:]
        for d in detections where d.confidence >= minConfidence && (SceneCatalog.tier(d.label, overrides: tiers) ?? .off) != .off {
            if let old = nearest[d.label], (old.distance ?? .infinity) <= (d.distance ?? .infinity) { continue }
            nearest[d.label] = d
        }
        for d in nearest.values {
            let info = SceneClass(name: SceneCatalog.classes[d.label]!.name, tier: SceneCatalog.tier(d.label, overrides: tiers)!)
            let priority: SpeechPriority
            if info.tier == .hazard { guard let p = NoticeFilter.hazardPriority(d.distance, critical: closeDistance, announce: announceDistance) else { continue }; priority = p } else { priority = info.tier.speech }
            items.append(SceneItem(priority: priority, text: NoticeFilter.text(d, name: info.name, close: closeDistance), distance: d.distance))
        }
        return Array(items.enumerated().sorted { a, b in
            if a.element.priority != b.element.priority { return a.element.priority > b.element.priority }
            let da = a.element.distance ?? .infinity, db = b.element.distance ?? .infinity
            return da != db ? da < db : a.offset < b.offset
        }.map(\.element).prefix(limit))
    }
}
