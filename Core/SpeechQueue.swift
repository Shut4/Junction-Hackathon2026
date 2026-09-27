import Foundation
/// How urgently a message must reach the user. Higher interrupts lower and is spoken first.
public enum SpeechPriority: Int, Sendable, Comparable, CaseIterable {
    /// Surroundings that are nice to know (vending machine, tree).
    case low
    /// Route instructions and landmarks (braille block, crosswalk).
    case normal
    /// Obstacles and hazards in the path.
    case high
    /// Immediate danger: stop now.
    case critical
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    /// Default lifetime in the queue: urgent messages go stale fastest.
    var defaultTTL: Double { switch self { case .critical: 2; case .high: 2.5; case .normal: 6; case .low: 4 } }
}
public struct SpeechJob: Sendable {
    public let text:String;public let priority:SpeechPriority;public let route:Bool;public let generation:Int;public let expires:Date;public let detectionTime:Double?
}
public struct SpeechQueue: Sendable {
    private var jobs:[SpeechJob]=[]
    public private(set) var generation=0
    public var count:Int { jobs.count }
    public init() {}
    /// `route` jobs belong to the current route and are dropped by `invalidateRoute()`. `ttl` overrides the default lifetime.
    @discardableResult public mutating func enqueue(_ text:String,priority:SpeechPriority,route:Bool=false,now:Date=Date(),capturedAt:Double?=nil,ttl:Double?=nil)->Bool {
        guard !jobs.contains(where:{$0.text==text}) else { return false }
        jobs.append(SpeechJob(text:text,priority:priority,route:route,generation:generation,expires:now.addingTimeInterval(ttl ?? (route ? 12:priority.defaultTTL)),detectionTime:capturedAt))
        // Stable priority ordering prevents equal-priority notices from changing order.
        jobs=jobs.enumerated().sorted { $0.element.priority == $1.element.priority ? $0.offset < $1.offset:$0.element.priority > $1.element.priority }.map(\.element)
        return true
    }
    /// Legacy form: obstacle = high, otherwise a normal route message.
    @discardableResult public mutating func enqueue(_ text:String,obstacle:Bool,now:Date=Date(),capturedAt:Double?=nil,ttl:Double?=nil)->Bool {
        enqueue(text,priority:obstacle ? .high:.normal,route:!obstacle,now:now,capturedAt:capturedAt,ttl:ttl ?? (obstacle ? 2:12))
    }
    public mutating func invalidateRoute() { generation += 1;jobs.removeAll { $0.route } }
    public mutating func stop() { generation += 1;jobs.removeAll() }
    public mutating func next(now:Date=Date())->SpeechJob? {
        while !jobs.isEmpty { let job=jobs.removeFirst();if job.expires>now && (!job.route || job.generation==generation) { return job } }
        return nil
    }
}
