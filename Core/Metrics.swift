import Foundation
public struct MetricEvent: Codable, Sendable {
    public var kind:String;public var frame:Double?;public var inferenceStart:Double?;public var inferenceEnd:Double?;public var decision:Double?;public var speechStart:Double?;public var simulated:Bool
    public init(kind:String,frame:Double?=nil,inferenceStart:Double?=nil,inferenceEnd:Double?=nil,decision:Double?=nil,speechStart:Double?=nil,simulated:Bool=false) { self.kind=kind;self.frame=frame;self.inferenceStart=inferenceStart;self.inferenceEnd=inferenceEnd;self.decision=decision;self.speechStart=speechStart;self.simulated=simulated }
}
