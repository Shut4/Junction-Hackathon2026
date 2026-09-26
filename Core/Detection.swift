import Foundation
public struct Box: Sendable { public var x: Double; public var y: Double; public var width: Double; public var height: Double
    public init(x: Double,y: Double,width: Double,height: Double) { self.x=x;self.y=y;self.width=width;self.height=height }
    public func iou(_ other: Box) -> Double {
        let intersection = max(0,min(x+width,other.x+other.width)-max(x,other.x))*max(0,min(y+height,other.y+other.height)-max(y,other.y))
        return intersection/max(0.00001,width*height+other.width*other.height-intersection)
    }
}
public struct Detection: Sendable { public var label: String; public var confidence: Double; public var box: Box; public var capturedAt: TimeInterval; public var simulated: Bool
    public init(label:String,confidence:Double,box:Box,capturedAt:TimeInterval,simulated:Bool=false) { self.label=label;self.confidence=confidence;self.box=box;self.capturedAt=capturedAt;self.simulated=simulated }
}
/// Japanese names for the model classes that produce spoken notices. Shared by the filter and the UI.
public enum DetectionLabels {
    public static let japanese = ["pole":"ポール","stairs":"階段","steps":"段差","bollard":"車止め","safety-cone":"コーン","person":"人","bicycle":"自転車"]
}
public struct DetectionNotice: Sendable { public var label: String; public var text: String; public var capturedAt: TimeInterval }
public struct NoticeFilter: Sendable {
    private struct Track: Sendable { var box: Box; var first: Double; var last: Double; var notified: Double? }
    private var tracks: [String:[Track]] = [:]
    private var classLast: [String:Double] = [:]
    public var confidence = 0.6; public var persistence = 0.6; public var cooldown = 8.0
    public private(set) var notices = 0; public private(set) var suppressed = 0
    public init() {}
    public mutating func reset() { tracks.removeAll();classLast.removeAll() }
    public mutating func process(_ detections: [Detection], now: Double) -> [DetectionNotice] {
        let names = DetectionLabels.japanese
        for k in Array(tracks.keys) { tracks[k]?.removeAll { now-$0.last > 1.5 } }
        var result: [DetectionNotice] = []
        for d in detections where d.confidence >= confidence && now-d.capturedAt <= 1 && now-d.capturedAt >= 0 {
            guard let name = names[d.label] else { continue }
            var list = tracks[d.label,default:[]]
            let index = list.indices.max { list[$0].box.iou(d.box) < list[$1].box.iou(d.box) }
            let match = index.flatMap { list[$0].box.iou(d.box) >= 0.2 ? $0 : nil }
            let i: Int
            if let match { i=match;list[i].box=d.box;list[i].last=now } else { list.append(Track(box:d.box,first:now,last:now));i=list.count-1 }
            if now-list[i].first >= persistence {
                if list[i].notified == nil && now-classLast[d.label,default: -.infinity] >= cooldown {
                    result.append(DetectionNotice(label:d.label,text:"カメラに\(name)を検出しました。",capturedAt:d.capturedAt)); list[i].notified=now;classLast[d.label]=now;notices += 1
                } else { suppressed += 1 }
            }
            tracks[d.label]=list
        }
        return result
    }
}
