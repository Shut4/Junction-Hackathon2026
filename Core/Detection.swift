import Foundation
public struct Box: Sendable { public var x: Double; public var y: Double; public var width: Double; public var height: Double
    public init(x: Double,y: Double,width: Double,height: Double) { self.x=x;self.y=y;self.width=width;self.height=height }
    public func iou(_ other: Box) -> Double {
        let intersection = max(0,min(x+width,other.x+other.width)-max(x,other.x))*max(0,min(y+height,other.y+other.height)-max(y,other.y))
        return intersection/max(0.00001,width*height+other.width*other.height-intersection)
    }
}
/// `distance`/`lateral` (m, positive lateral = right) come from the camera depth when available.
public struct Detection: Sendable { public var label: String; public var confidence: Double; public var box: Box; public var capturedAt: TimeInterval; public var simulated: Bool
    public var distance: Double?; public var lateral: Double?
    /// Set when depth shows the detection is implausible (e.g. a picture on a screen); such detections are never spoken or marked.
    public var rejected: String?
    public init(label:String,confidence:Double,box:Box,capturedAt:TimeInterval,simulated:Bool=false,distance:Double?=nil,lateral:Double?=nil,rejected:String?=nil) { self.label=label;self.confidence=confidence;self.box=box;self.capturedAt=capturedAt;self.simulated=simulated;self.distance=distance;self.lateral=lateral;self.rejected=rejected }
    /// Side as heard by the walker: depth lateral when known, else the box centre in the portrait image.
    public var side: String {
        if let lateral { return lateral > 0.3 ? "右" : lateral < -0.3 ? "左" : "正面" }
        let centre = box.x + box.width/2
        return centre > 0.65 ? "右" : centre < 0.35 ? "左" : "正面"
    }
}

/// How useful a class is to a blind or low-vision walker. Decides speech priority, repeat rate and display order.
public enum SceneTier: Int, Sendable, Comparable, CaseIterable, Codable {
    /// Never spoken or marked (DeveloperMode override for classes that misfire).
    case off = -1
    /// Nice-to-know surroundings; spoken only when enabled.
    case context
    /// Wayfinding cues: braille blocks, crosswalks, signals, doors.
    case landmark
    /// Things to avoid in the path: steps, poles, people, vehicles.
    case hazard
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    public var speech: SpeechPriority { switch self { case .hazard: .high; case .landmark: .normal; case .context, .off: .low } }
    public var japanese: String { switch self { case .hazard: "危険"; case .landmark: "目印"; case .context: "周辺"; case .off: "読まない" } }
}
public struct SceneClass: Sendable { public let name: String; public let tier: SceneTier }
/// The 39 VIDVIP classes. Signal colours are deliberately not spoken: crossing decisions stay with the user and companion.
/// People and vehicles are landmarks (spoken, no warning sound), except bicycles, cyclists and motorbikes, which are hidden
/// (frequent false detections). DeveloperMode can change any label's tier.
public enum SceneCatalog {
    /// Classes with many false detections start from a stricter confidence threshold than the common one.
    public static let defaultConfidence: [String: Double] = ["motorbike": 0.8, "bicycler": 0.8]
    /// Confidence threshold for a label: DeveloperMode override, else the class default, else the common value.
    public static func threshold(_ label: String, overrides: [String: Double] = [:], common: Double) -> Double { overrides[label] ?? defaultConfidence[label] ?? common }
    /// Tier for a label with DeveloperMode overrides applied; nil for labels outside the catalogue.
    public static func tier(_ label: String, overrides: [String: SceneTier] = [:]) -> SceneTier? { overrides[label] ?? classes[label]?.tier }
    public static let classes: [String: SceneClass] = [
        "stairs": .init(name:"階段",tier:.hazard),"steps": .init(name:"段差",tier:.hazard),"pole": .init(name:"ポール",tier:.hazard),
        "bollard": .init(name:"車止め",tier:.hazard),"safety-cone": .init(name:"コーン",tier:.hazard),"person": .init(name:"人",tier:.landmark),
        "bicycle": .init(name:"自転車",tier:.off),"bicycler": .init(name:"自転車に乗った人",tier:.off),"motorbike": .init(name:"バイク",tier:.off),
        "car": .init(name:"車",tier:.landmark),"bus": .init(name:"バス",tier:.landmark),"truck": .init(name:"トラック",tier:.landmark),
        "braille_block": .init(name:"点字ブロック",tier:.landmark),"crosswalk": .init(name:"横断歩道",tier:.landmark),
        "signal_red": .init(name:"歩行者信号",tier:.landmark),"signal_blue": .init(name:"歩行者信号",tier:.landmark),"traffic_light": .init(name:"信号機",tier:.landmark),
        "signal_button": .init(name:"押しボタン",tier:.landmark),"handrail": .init(name:"手すり",tier:.landmark),"elevator": .init(name:"エレベーター",tier:.context),
        "escalator": .init(name:"エスカレーター",tier:.off),"faregates": .init(name:"改札",tier:.context),"door": .init(name:"ドア",tier:.context),
        "bus_stop_sign": .init(name:"バス停",tier:.landmark),"bathroom": .init(name:"トイレ",tier:.context),"guardrail": .init(name:"ガードレール",tier:.hazard),
        "white_line": .init(name:"白線",tier:.context),"fence": .init(name:"フェンス",tier:.context),"wall": .init(name:"壁",tier:.context),
        "tree": .init(name:"木",tier:.context),"shrubs": .init(name:"植え込み",tier:.context),"signboard": .init(name:"看板",tier:.context),
        "vending_machine": .init(name:"自動販売機",tier:.context),"postbox": .init(name:"ポスト",tier:.off),"train_ticket_machine": .init(name:"券売機",tier:.off),
        "flag": .init(name:"旗",tier:.off),"monument": .init(name:"記念碑",tier:.off),"train": .init(name:"電車",tier:.off),"boat": .init(name:"船",tier:.off),
    ]
}
/// Japanese names for the model classes. Shared by the filter and the UI.
public enum DetectionLabels {
    public static let japanese = SceneCatalog.classes.mapValues(\.name)
}
/// `hazard` = from the hazard tier, so it gets the warning beep (and vibration when high/critical) even when far ("normal").
public struct DetectionNotice: Sendable { public var label: String; public var text: String; public var capturedAt: TimeInterval; public var priority: SpeechPriority = .high; public var hazard = true }
/// DeveloperMode tuning of object notices, persisted between launches. Variable names match the DeveloperMode labels.
public struct NoticeTuning: Sendable, Codable, Equatable {
    public var confidence = 0.6, persistence = 0.6, cooldown = 8.0
    /// Class cooldown per tier as a multiple of `cooldown`.
    public var hazardCooldown = 1.0, landmarkCooldown = 2.5, contextCooldown = 6.0
    public var hazardRepeat = 10.0, criticalDistance = NoticeFilter.closeDistance
    /// Hazards are announced only within this distance (m); farther ones are ignored. Without depth they are announced as "high".
    public var announceDistance = 3.0
    /// Per-label tier overrides (label → tier); labels not listed keep their `SceneCatalog` tier.
    public var tiers: [String: SceneTier] = [:]
    /// Per-label confidence thresholds; labels not listed use `confidence`.
    public var classConfidence: [String: Double] = [:]
    public func confidence(for label: String) -> Double { SceneCatalog.threshold(label, overrides: classConfidence, common: confidence) }
    public init() {}
    /// Tolerates values saved before a field existed: missing keys keep their defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self), d = NoticeTuning()
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence) ?? d.confidence
        persistence = try c.decodeIfPresent(Double.self, forKey: .persistence) ?? d.persistence
        cooldown = try c.decodeIfPresent(Double.self, forKey: .cooldown) ?? d.cooldown
        hazardCooldown = try c.decodeIfPresent(Double.self, forKey: .hazardCooldown) ?? d.hazardCooldown
        landmarkCooldown = try c.decodeIfPresent(Double.self, forKey: .landmarkCooldown) ?? d.landmarkCooldown
        contextCooldown = try c.decodeIfPresent(Double.self, forKey: .contextCooldown) ?? d.contextCooldown
        hazardRepeat = try c.decodeIfPresent(Double.self, forKey: .hazardRepeat) ?? d.hazardRepeat
        criticalDistance = try c.decodeIfPresent(Double.self, forKey: .criticalDistance) ?? d.criticalDistance
        announceDistance = try c.decodeIfPresent(Double.self, forKey: .announceDistance) ?? d.announceDistance
        tiers = try c.decodeIfPresent([String: SceneTier].self, forKey: .tiers) ?? [:]
        classConfidence = try c.decodeIfPresent([String: Double].self, forKey: .classConfidence) ?? [:]
    }
    public func apply(to f: inout NoticeFilter) {
        f.confidence = confidence; f.persistence = persistence; f.cooldown = cooldown
        f.tierCooldown = [.hazard: hazardCooldown, .landmark: landmarkCooldown, .context: contextCooldown]
        f.hazardRepeat = hazardRepeat; f.criticalDistance = criticalDistance; f.announceDistance = announceDistance; f.tierOverrides = tiers; f.classConfidence = classConfidence
    }
}
public struct NoticeFilter: Sendable {
    private struct Track: Sendable { var box: Box; var first: Double; var last: Double; var notified: Double? }
    private var tracks: [String:[Track]] = [:]
    private var classLast: [String:Double] = [:]
    public var confidence = 0.6; public var persistence = 0.6; public var cooldown = 8.0
    /// Lowest tier that is spoken. `context` classes are off unless the user enables them.
    public var minimumTier: SceneTier = .landmark
    /// DeveloperMode per-label tier overrides and confidence thresholds.
    public var tierOverrides: [String: SceneTier] = [:]
    public var classConfidence: [String: Double] = [:]
    /// Per-tier class cooldown, as a multiple of `cooldown`: hazards most often, surroundings rarely.
    public var tierCooldown: [SceneTier: Double] = [.hazard: 1, .landmark: 2.5, .context: 6]
    /// Hazards still in view are repeated after this many seconds; other tiers are said once per appearance.
    public var hazardRepeat = 10.0
    /// Hazards closer than this (m, from depth) are raised to critical and said as 「目の前」.
    public static let closeDistance = 2.0
    public var criticalDistance = NoticeFilter.closeDistance
    public var announceDistance = 3.0
    /// Priority of a hazard by distance: critical within `critical`, high within `announce` (or unknown distance), nil beyond (not announced).
    public static func hazardPriority(_ distance: Double?, critical: Double, announce: Double) -> SpeechPriority? {
        guard let distance else { return .high }
        return distance <= critical ? .critical : distance <= announce ? .high : nil
    }
    public private(set) var notices = 0; public private(set) var suppressed = 0
    public init() {}
    public mutating func reset() { tracks.removeAll();classLast.removeAll() }
    public mutating func process(_ detections: [Detection], now: Double) -> [DetectionNotice] {
        for k in Array(tracks.keys) { tracks[k]?.removeAll { now-$0.last > 1.5 } }
        var result: [DetectionNotice] = []
        for d in detections where d.rejected == nil && d.confidence >= SceneCatalog.threshold(d.label, overrides: classConfidence, common: confidence) && now-d.capturedAt <= 1 && now-d.capturedAt >= 0 {
            guard let base = SceneCatalog.classes[d.label], let tier = SceneCatalog.tier(d.label, overrides: tierOverrides), tier != .off, tier >= minimumTier else { continue }
            let info = SceneClass(name: base.name, tier: tier)
            var list = tracks[d.label,default:[]]
            let index = list.indices.max { list[$0].box.iou(d.box) < list[$1].box.iou(d.box) }
            let match = index.flatMap { list[$0].box.iou(d.box) >= 0.2 ? $0 : nil }
            let i: Int
            if let match { i=match;list[i].box=d.box;list[i].last=now } else { list.append(Track(box:d.box,first:now,last:now));i=list.count-1 }
            // Hazards beyond the announce distance are not tracked for speech at all.
            if info.tier == .hazard, Self.hazardPriority(d.distance, critical: criticalDistance, announce: announceDistance) == nil { tracks[d.label]=list; continue }
            if now-list[i].first >= persistence {
                let due = list[i].notified.map { info.tier == .hazard && now-$0 >= hazardRepeat } ?? true
                if due && now-classLast[d.label,default: -.infinity] >= cooldown*tierCooldown[info.tier,default:1] {
                    let priority = info.tier == .hazard ? Self.hazardPriority(d.distance, critical: criticalDistance, announce: announceDistance) ?? .high : info.tier.speech
                    result.append(DetectionNotice(label:d.label,text:Self.text(d,name:info.name,close:criticalDistance),capturedAt:d.capturedAt,priority:priority,hazard:info.tier == .hazard))
                    list[i].notified=now;classLast[d.label]=now;notices += 1
                } else { suppressed += 1 }
            }
            tracks[d.label]=list
        }
        // Most urgent first, so a later low-priority notice never delays a hazard.
        return result.sorted { $0.priority > $1.priority }
    }
    /// Short and without metres, e.g. 「目の前に段差。」「左前にポール。」. Closeness is conveyed by priority and vibration.
    public static func text(_ d: Detection, name: String, close: Double = closeDistance) -> String {
        coreLocalized("{0}に{1}。", position(side: d.side, close: (d.distance ?? .infinity) <= close), coreLocalized(name))
    }
    /// 「目の前」「すぐ左」「すぐ右」 when close, else 「前方」「左前」「右前」.
    public static func position(side: String, close: Bool) -> String {
        coreLocalized(side == "左" ? (close ? "すぐ左" : "左前") : side == "右" ? (close ? "すぐ右" : "右前") : (close ? "目の前" : "前方"))
    }
}
