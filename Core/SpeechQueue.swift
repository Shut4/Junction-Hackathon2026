import Foundation
public struct SpeechJob: Sendable {
    public let text:String;public let priority:Int;public let generation:Int;public let expires:Date;public let detectionTime:Double?
}
public struct SpeechQueue: Sendable {
    private var jobs:[SpeechJob]=[]
    public private(set) var generation=0
    public var count:Int { jobs.count }
    public init() {}
    @discardableResult public mutating func enqueue(_ text:String,obstacle:Bool,now:Date=Date(),capturedAt:Double?=nil)->Bool {
        guard !jobs.contains(where:{$0.text==text}) else { return false }
        jobs.append(SpeechJob(text:text,priority:obstacle ? 1:0,generation:generation,expires:now.addingTimeInterval(obstacle ? 2:12),detectionTime:capturedAt))
        // Stable priority ordering prevents equal-priority notices from changing order.
        jobs=jobs.enumerated().sorted { $0.element.priority == $1.element.priority ? $0.offset < $1.offset:$0.element.priority > $1.element.priority }.map(\.element)
        return true
    }
    public mutating func invalidateRoute() { generation += 1;jobs.removeAll { $0.priority==0 } }
    public mutating func stop() { generation += 1;jobs.removeAll() }
    public mutating func next(now:Date=Date())->SpeechJob? {
        while !jobs.isEmpty { let job=jobs.removeFirst();if job.expires>now && (job.priority>0 || job.generation==generation) { return job } }
        return nil
    }
}
