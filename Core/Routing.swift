import Foundation
public struct RouteStep: Identifiable, Sendable { public var id: String; public var from: String; public var to: String; public var distance: Double; public var shape: [Coordinate] }
public struct WalkRoute: Sendable { public var steps: [RouteStep]; public var distance: Double; public var destinationID: String }
public struct Router: Sendable {
    public var network: Network
    private let adjacency: [String: [Int]]
    private let nodeIDs: Set<String>
    public init(network: Network) {
        self.network = network
        var adjacency: [String: [Int]] = [:]
        for (i, e) in network.edges.enumerated() { adjacency[e.from, default: []].append(i); if e.to != e.from { adjacency[e.to, default: []].append(i) } }
        self.adjacency = adjacency; nodeIDs = Set(network.nodes.map(\.id))
    }
    public func route(from start: String, to end: String, blocked: Set<String>) -> WalkRoute? {
        guard nodeIDs.contains(start), nodeIDs.contains(end) else { return nil }
        var costs: [String: Double] = [start: 0], previous: [String: RouteStep] = [:], visited = Set<String>(), heap = MinHeap()
        heap.push(0, start)
        while let (cost, current) = heap.pop() {
            if visited.contains(current) { continue }
            if current == end { break }; visited.insert(current)
            for i in adjacency[current] ?? [] {
                let edge = network.edges[i]; guard !blocked.contains(edge.id) else { continue }
                var step: RouteStep?
                if edge.from == current && edge.direction != "backward" { step = RouteStep(id: edge.id, from: edge.from, to: edge.to, distance: edge.distance, shape: edge.shape) }
                else if edge.to == current && edge.direction != "forward" { step = RouteStep(id: edge.id, from: edge.to, to: edge.from, distance: edge.distance, shape: edge.shape.reversed()) }
                if let s = step, !visited.contains(s.to), cost + s.distance < costs[s.to, default: .infinity] { costs[s.to] = cost + s.distance; previous[s.to] = s; heap.push(cost + s.distance, s.to) }
            }
        }
        guard let distance = costs[end] else { return nil }
        var steps: [RouteStep] = [], cursor = end
        while cursor != start { guard let step = previous[cursor] else { return nil }; steps.insert(step, at: 0); cursor = step.from }
        return WalkRoute(steps: steps, distance: distance, destinationID: end)
    }
    public func route(from p: Coordinate, on edgeID: String, to end: String, blocked: Set<String>) -> WalkRoute? {
        guard let e = network.edges.first(where: { $0.id == edgeID }), !blocked.contains(e.id) else { return nil }
        let projection = Geometry.project(p, onto: e.shape)
        var options: [WalkRoute] = []
        for (node,fraction,allowed) in [(e.from,projection.fraction,e.direction != "forward"),(e.to,1-projection.fraction,e.direction != "backward")] where allowed {
            if var route = route(from: node, to: end, blocked: blocked), let target = network.nodes.first(where: { $0.id == node }) {
                let towardsEnd = node == e.to
                let lengths = zip(e.shape,e.shape.dropFirst()).map { $0.0.distance(to:$0.1) }
                let offset = projection.fraction * e.distance
                var traveled = 0.0, partial: [Coordinate] = [projection.coordinate]
                for (i,c) in e.shape.enumerated() {
                    if (towardsEnd && traveled > offset) || (!towardsEnd && traveled < offset) { partial.append(c) }
                    if i < lengths.count { traveled += lengths[i] }
                }
                if !towardsEnd { partial = [projection.coordinate]+partial.dropFirst().reversed() }
                if partial.last != target.coordinate { partial.append(target.coordinate) }
                let distance = fraction*e.distance
                if distance > 0.1 { route.steps.insert(RouteStep(id:e.id,from:"current",to:node,distance:distance,shape:partial),at:0) }
                route.distance += distance; options.append(route)
            }
        }
        return options.min { $0.distance < $1.distance }
    }
}
public struct LocationSample: Sendable {
    public var coordinate: Coordinate; public var accuracy: Double; public var timestamp: Date; public var simulated: Bool
    public var course:Double;public var courseAccuracy:Double;public var speed:Double
    public init(coordinate: Coordinate, accuracy: Double, timestamp: Date, simulated: Bool = false,course:Double = -1,courseAccuracy:Double = -1,speed:Double = -1) { self.coordinate = coordinate; self.accuracy = accuracy; self.timestamp = timestamp; self.simulated = simulated;self.course=course;self.courseAccuracy=courseAccuracy;self.speed=speed }
}
public enum TurnGuidance {
    public static func instruction(current:RouteStep,next:RouteStep?,sample:LocationSample)->String? {
        guard sample.course >= 0,sample.courseAccuracy >= 0,sample.courseAccuracy <= 20,sample.speed >= 0.5,sample.accuracy <= 10,current.shape.count >= 2 else { return nil }
        let projected=Geometry.project(sample.coordinate,onto:current.shape)
        let diff=abs((sample.course-projected.bearing+540).truncatingRemainder(dividingBy:360)-180)
        guard diff<=30 else { return nil }
        guard let next,next.shape.count>=2 else { return "経路に沿って進みます。" }
        let incoming=Geometry.bearing(current.shape[current.shape.count-2],current.shape.last!),outgoing=Geometry.bearing(next.shape[0],next.shape[1])
        let angle=(outgoing-incoming+540).truncatingRemainder(dividingBy:360)-180
        if abs(angle)<25 { return "次の接続点で経路に沿って直進します。" }
        if abs(angle)>150 { return "次の接続点で折り返す経路です。同行者と向きを確認してください。" }
        return "次の接続点で\(angle>0 ? "右":"左")に曲がる経路です。横断箇所と足元を同行者と確認してください。"
    }
}
public enum LocationVerdict: Sendable { case matched(String), uncertain(String), outside }
public enum PositionGate {
    public static func evaluate(_ p: LocationSample, network: Network, now: Date = Date()) -> LocationVerdict {
        guard p.accuracy >= 0, p.accuracy <= 20, now.timeIntervalSince(p.timestamp) >= -2, now.timeIntervalSince(p.timestamp) <= 8 else { return .uncertain("位置の精度または更新時刻を確認中です。案内を保留します。") }
        guard network.bounds.contains(p.coordinate) else { return .outside }
        let options = RoadMatcher(network: network).candidates(at:p.coordinate,radius:max(10,p.accuracy))
        guard let first = options.first else { return .uncertain("位置に対応する歩行区間がありません。") }
        if options.count > 1 && options[1].distance-first.distance < max(5,p.accuracy) { return .uncertain("道路候補が複数あります。方向案内を保留します。") }
        return .matched(first.id)
    }
}
public struct PositionResolver: Sendable {
    private var candidate:String?
    private var count=0
    private var lastSample:LocationSample?
    public init() {}
    public mutating func reset() { candidate=nil;count=0;lastSample=nil }
    public mutating func evaluate(_ sample:LocationSample,network:Network,now:Date=Date())->LocationVerdict {
        let verdict=PositionGate.evaluate(sample,network:network,now:now)
        guard case .matched(let id)=verdict else { candidate=nil;count=0;return verdict }
        if let previous=lastSample,previous.timestamp != sample.timestamp {
            let elapsed=sample.timestamp.timeIntervalSince(previous.timestamp)
            guard elapsed>0,previous.simulated==sample.simulated,sample.coordinate.distance(to:previous.coordinate)<=max(15,elapsed*4+previous.accuracy+sample.accuracy) else { reset();return .uncertain("位置の移動が不連続です。道路との対応を再確認します。") }
        }
        if candidate != id { candidate=id;count=0 }
        if lastSample?.timestamp != sample.timestamp { count += 1;lastSample=sample }
        return count>=3 ? .matched(id):.uncertain("道路候補の継続を確認中です。方向案内を保留します。")
    }
}
private struct MinHeap {
    private var items: [(Double, String)] = []
    mutating func push(_ cost: Double, _ node: String) {
        items.append((cost, node)); var i = items.count - 1
        while i > 0 { let parent = (i - 1) / 2; guard items[i].0 < items[parent].0 else { break }; items.swapAt(i, parent); i = parent }
    }
    mutating func pop() -> (Double, String)? {
        guard !items.isEmpty else { return nil }
        items.swapAt(0, items.count - 1); let top = items.removeLast(); var i = 0
        while true {
            let l = 2 * i + 1, r = l + 1; var m = i
            if l < items.count && items[l].0 < items[m].0 { m = l }
            if r < items.count && items[r].0 < items[m].0 { m = r }
            if m == i { break }; items.swapAt(i, m); i = m
        }
        return top
    }
}
