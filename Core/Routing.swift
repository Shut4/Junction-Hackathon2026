import Foundation
public struct RouteStep: Identifiable, Sendable { public var id: String; public var from: String; public var to: String; public var distance: Double; public var shape: [Coordinate] }
extension RouteStep {
    /// Pseudo step from an off-road position straight to the nearest usable road. Not a network edge.
    public static let approachID = "approach"
    public var isApproach: Bool { id == Self.approachID }
}
public struct WalkRoute: Sendable {
    public var steps: [RouteStep]
    public var distance: Double
    public var destinationID: String
    public var destinationCoordinate: Coordinate
    /// Exact closure snapshot supplied to the search that produced this route.
    /// Keeping this with the result prevents the UI from describing a newer or older search state.
    public var excludedSegmentIDs: Set<String>
    public var excludedSegmentCount: Int { excludedSegmentIDs.count }
    public var blockedSegmentsInRoute: Set<String> { Set(steps.map(\.id)).intersection(excludedSegmentIDs) }
}
public struct DestinationRoute: Sendable {
    public var connection: DestinationConnection
    public var route: WalkRoute
}
public enum RouteFailure: Error, Equatable, Sendable {
    case unmatchedPosition, blockedStart, blockedDestination, outsideNetwork, noRoute
    public var message:String {
        switch self {
        case .unmatchedPosition: return "現在位置に対応する道路がありません。位置情報と選択地域を確認してください。"
        case .blockedStart: return "現在位置の道路が通行不可に登録されています。経路案内を開始できません。"
        case .blockedDestination: return "目的地付近の道路が通行不可です。目的地を選び直すか、通行不可の登録状況を確認してください。"
        case .outsideNetwork: return "現在位置または目的地が選択地域の対応範囲外です。地域をまたぐ経路には対応していません。"
        case .noRoute: return "目的地まで到達できる経路がありません。別の目的地を選ぶか、道路網の接続と通行不可の登録状況を確認してください。"
        }
    }
}
public struct Router: Sendable {
    public var network: Network
    private let adjacency: [String: [Int]]
    private let nodeIDs: Set<String>
    private let edgeByID: [String: WalkEdge]
    private let nodeByID: [String: Place]
    public init(network: Network) {
        self.network = network
        var adjacency: [String: [Int]] = [:]
        for (i, e) in network.edges.enumerated() { adjacency[e.from, default: []].append(i); if e.to != e.from { adjacency[e.to, default: []].append(i) } }
        self.adjacency = adjacency
        nodeIDs = Set(network.nodes.map(\.id))
        edgeByID = Dictionary(network.edges.map { ($0.id,$0) },uniquingKeysWith:{ first,_ in first })
        nodeByID = Dictionary(network.nodes.map { ($0.id,$0) },uniquingKeysWith:{ first,_ in first })
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
        var reversedSteps: [RouteStep] = [], cursor = end
        while cursor != start { guard let step = previous[cursor] else { return nil }; reversedSteps.append(step); cursor = step.from }
        let steps=Array(reversedSteps.reversed())
        guard let destinationCoordinate=nodeByID[end]?.coordinate else { return nil }
        let result=WalkRoute(steps:steps,distance:distance,destinationID:end,destinationCoordinate:destinationCoordinate,excludedSegmentIDs:blocked)
        // This is intentionally checked at the Core boundary as well as before display.
        // A future routing optimization must never turn a blocked edge into a fallback.
        guard result.blockedSegmentsInRoute.isEmpty else { return nil }
        return result
    }
    public func resolveRoute(from p:Coordinate,on edgeID:String,to end:String,blocked:Set<String>)->Result<WalkRoute,RouteFailure> {
        guard network.bounds.contains(p),nodeIDs.contains(end) else { return .failure(.outsideNetwork) }
        guard network.edges.contains(where: { $0.id == edgeID }) else { return .failure(.unmatchedPosition) }
        guard !blocked.contains(edgeID) else { return .failure(.blockedStart) }
        guard let route=route(from:p,on:edgeID,to:end,blocked:blocked) else { return .failure(.noRoute) }
        return .success(route)
    }
    /// Route from a position that is not on any road (inside the region): a straight approach step to a nearby
    /// unblocked edge, then the network route. Of the edges near the closest one, picks the shortest total.
    public func resolveOffRoadRoute(from p:Coordinate,to end:String,blocked:Set<String>,slack:Double=30,limit:Int=8)->Result<WalkRoute,RouteFailure> {
        guard network.bounds.contains(p),nodeIDs.contains(end) else { return .failure(.outsideNetwork) }
        let near=network.edges.filter { !blocked.contains($0.id) }.map { ($0.id,Geometry.project(p,onto:$0.shape)) }.sorted { $0.1.distance < $1.1.distance }
        guard let closest=near.first?.1.distance else { return .failure(.noRoute) }
        var best:WalkRoute?
        for (id,projection) in near.prefix(limit) where projection.distance <= closest+slack {
            guard var found=route(from:p,on:id,to:end,blocked:blocked) else { continue }
            found.steps.insert(RouteStep(id:RouteStep.approachID,from:"current",to:"entry",distance:projection.distance,shape:[p,projection.coordinate]),at:0)
            found.distance += projection.distance
            if best == nil || found.distance < best!.distance { best=found }
        }
        return best.map { .success($0) } ?? .failure(.noRoute)
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

    /// Route to an exact point on a saved road. The unverified gap from the user's selected place to this
    /// endpoint is intentionally not part of the route.
    public func route(from start:String,to connection:DestinationConnection,blocked:Set<String>)->WalkRoute? {
        guard nodeIDs.contains(start),let edge=network.edge(connection.edgeID),!blocked.contains(edge.id) else { return nil }
        let fraction=min(1,max(0,connection.fraction))
        var options:[WalkRoute]=[]
        for (node,startFraction,allowed) in [(edge.from,0.0,edge.direction != "backward"),(edge.to,1.0,edge.direction != "forward")] where allowed {
            guard var found=route(from:start,to:node,blocked:blocked) else { continue }
            let distance=abs(fraction-startFraction)*edge.distance
            if distance>0.1 {
                found.steps.append(RouteStep(id:edge.id,from:node,to:"destination",distance:distance,shape:Geometry.slice(edge.shape,from:startFraction,to:fraction)))
                found.distance += distance
            }
            found.destinationID="connection:"+edge.id
            found.destinationCoordinate=connection.coordinate
            options.append(found)
        }
        return options.min { $0.distance<$1.distance }
    }

    public func resolveRoute(from p:Coordinate,on edgeID:String,to connection:DestinationConnection,blocked:Set<String>)->Result<WalkRoute,RouteFailure> {
        guard network.bounds.contains(p),network.edge(connection.edgeID) != nil else { return .failure(.outsideNetwork) }
        guard let startEdge=network.edge(edgeID) else { return .failure(.unmatchedPosition) }
        guard !blocked.contains(startEdge.id) else { return .failure(.blockedStart) }
        guard !blocked.contains(connection.edgeID) else { return .failure(.blockedDestination) }
        guard let route=route(from:p,on:edgeID,to:connection,blocked:blocked) else { return .failure(.noRoute) }
        return .success(route)
    }

    public func resolveOffRoadRoute(from p:Coordinate,to connection:DestinationConnection,blocked:Set<String>,slack:Double=30,limit:Int=8)->Result<WalkRoute,RouteFailure> {
        guard network.bounds.contains(p),network.edge(connection.edgeID) != nil else { return .failure(.outsideNetwork) }
        guard !blocked.contains(connection.edgeID) else { return .failure(.blockedDestination) }
        let near=network.edges.filter { !blocked.contains($0.id) }.map { ($0.id,Geometry.project(p,onto:$0.shape)) }.sorted { $0.1.distance<$1.1.distance }
        guard let closest=near.first?.1.distance else { return .failure(.noRoute) }
        var best:WalkRoute?
        for (id,projection) in near.prefix(limit) where projection.distance<=closest+slack {
            guard var found=route(from:p,on:id,to:connection,blocked:blocked) else { continue }
            found.steps.insert(RouteStep(id:RouteStep.approachID,from:"current",to:"entry",distance:projection.distance,shape:[p,projection.coordinate]),at:0)
            found.distance += projection.distance
            if best == nil || found.distance<best!.distance { best=found }
        }
        return best.map { .success($0) } ?? .failure(.noRoute)
    }

    public func route(from p:Coordinate,on edgeID:String,to connection:DestinationConnection,blocked:Set<String>)->WalkRoute? {
        guard let startEdge=network.edge(edgeID),let destinationEdge=network.edge(connection.edgeID),!blocked.contains(startEdge.id),!blocked.contains(destinationEdge.id) else { return nil }
        let start=Geometry.project(p,onto:startEdge.shape),destinationFraction=min(1,max(0,connection.fraction))
        var options:[WalkRoute]=[]

        if startEdge.id == destinationEdge.id {
            let forward=destinationFraction>=start.fraction
            if (forward && startEdge.direction != "backward") || (!forward && startEdge.direction != "forward") {
                let distance=abs(destinationFraction-start.fraction)*startEdge.distance
                let steps=distance>0.1 ? [RouteStep(id:startEdge.id,from:"current",to:"destination",distance:distance,shape:Geometry.slice(startEdge.shape,from:start.fraction,to:destinationFraction))]:[]
                options.append(WalkRoute(steps:steps,distance:distance,destinationID:"connection:"+destinationEdge.id,destinationCoordinate:connection.coordinate,excludedSegmentIDs:blocked))
            }
        }

        for (node,endFraction,allowed) in [(startEdge.from,0.0,startEdge.direction != "forward"),(startEdge.to,1.0,startEdge.direction != "backward")] where allowed {
            guard var found=route(from:node,to:connection,blocked:blocked) else { continue }
            let distance=abs(endFraction-start.fraction)*startEdge.distance
            if distance>0.1 {
                found.steps.insert(RouteStep(id:startEdge.id,from:"current",to:node,distance:distance,shape:Geometry.slice(startEdge.shape,from:start.fraction,to:endFraction)),at:0)
                found.distance += distance
            }
            options.append(found)
        }
        return options.min { $0.distance<$1.distance }
    }

    // MARK: Batched destination routing
    // Destination selection used to run a complete point-to-point search for every
    // candidate (and then repeat the winning search). These entry points seed one
    // shortest-path tree and score every candidate from that single traversal.
    public func bestRoute(from start:String,to connections:[DestinationConnection],blocked:Set<String>)->DestinationRoute? {
        guard nodeIDs.contains(start) else { return nil }
        return bestRoute(seeds:[SearchSeed(node:start,cost:0,prefix:[])],direct:[],connections:connections,blocked:blocked)
    }

    public func bestRoute(from p:Coordinate,on edgeID:String,to connections:[DestinationConnection],blocked:Set<String>)->Result<DestinationRoute,RouteFailure> {
        guard network.bounds.contains(p),connections.contains(where:{ edgeByID[$0.edgeID] != nil }) else { return .failure(.outsideNetwork) }
        guard let edge=edgeByID[edgeID] else { return .failure(.unmatchedPosition) }
        guard !blocked.contains(edgeID) else { return .failure(.blockedStart) }
        let entrance=entranceOptions(from:p,on:edge,approach:nil,connections:connections,blocked:blocked)
        guard let found=bestRoute(seeds:entrance.seeds,direct:entrance.direct,connections:connections,blocked:blocked) else { return .failure(destinationFailure(connections,blocked:blocked)) }
        return .success(found)
    }

    public func bestOffRoadRoute(from p:Coordinate,to connections:[DestinationConnection],blocked:Set<String>,slack:Double=30,limit:Int=8)->Result<DestinationRoute,RouteFailure> {
        guard network.bounds.contains(p),connections.contains(where:{ edgeByID[$0.edgeID] != nil }) else { return .failure(.outsideNetwork) }
        let near=network.edges.filter { !blocked.contains($0.id) }.map { ($0,Geometry.project(p,onto:$0.shape)) }.sorted { $0.1.distance<$1.1.distance }
        guard let closest=near.first?.1.distance else { return .failure(.noRoute) }
        var seeds:[SearchSeed]=[],direct:[DestinationRoute]=[]
        for (edge,projection) in near.prefix(limit) where projection.distance<=closest+slack {
            let approach=RouteStep(id:RouteStep.approachID,from:"current",to:"entry",distance:projection.distance,shape:[p,projection.coordinate])
            let entrance=entranceOptions(from:projection.coordinate,on:edge,approach:approach,connections:connections,blocked:blocked)
            seeds.append(contentsOf:entrance.seeds);direct.append(contentsOf:entrance.direct)
        }
        guard let found=bestRoute(seeds:seeds,direct:direct,connections:connections,blocked:blocked) else { return .failure(destinationFailure(connections,blocked:blocked)) }
        return .success(found)
    }

    private struct SearchSeed {
        var node:String
        var cost:Double
        var prefix:[RouteStep]
    }
    private struct ScoredEndpoint {
        var connection:DestinationConnection
        var node:String
        var fraction:Double
        var routeDistance:Double
        var score:Double
    }

    private func destinationFailure(_ connections:[DestinationConnection],blocked:Set<String>)->RouteFailure {
        let valid=connections.filter { edgeByID[$0.edgeID] != nil }
        return !valid.isEmpty && valid.allSatisfy { blocked.contains($0.edgeID) } ? .blockedDestination:.noRoute
    }

    private func entranceOptions(from p:Coordinate,on edge:WalkEdge,approach:RouteStep?,connections:[DestinationConnection],blocked:Set<String>)->(seeds:[SearchSeed],direct:[DestinationRoute]) {
        guard !blocked.contains(edge.id) else { return ([],[]) }
        let projection=Geometry.project(p,onto:edge.shape)
        var seeds:[SearchSeed]=[]
        for (node,endFraction,allowed) in [(edge.from,0.0,edge.direction != "forward"),(edge.to,1.0,edge.direction != "backward")] where allowed {
            let distance=abs(endFraction-projection.fraction)*edge.distance
            var prefix=approach.map { [$0] } ?? []
            if distance>0.1 { prefix.append(RouteStep(id:edge.id,from:approach == nil ? "current":"entry",to:node,distance:distance,shape:Geometry.slice(edge.shape,from:projection.fraction,to:endFraction))) }
            seeds.append(SearchSeed(node:node,cost:(approach?.distance ?? 0)+distance,prefix:prefix))
        }
        var direct:[DestinationRoute]=[]
        for connection in connections where connection.edgeID==edge.id && !blocked.contains(connection.edgeID) {
            let destinationFraction=min(1,max(0,connection.fraction)),forward=destinationFraction>=projection.fraction
            guard (forward && edge.direction != "backward") || (!forward && edge.direction != "forward") else { continue }
            let distance=abs(destinationFraction-projection.fraction)*edge.distance
            var steps=approach.map { [$0] } ?? []
            if distance>0.1 { steps.append(RouteStep(id:edge.id,from:approach == nil ? "current":"entry",to:"destination",distance:distance,shape:Geometry.slice(edge.shape,from:projection.fraction,to:destinationFraction))) }
            let total=(approach?.distance ?? 0)+distance
            direct.append(DestinationRoute(connection:connection,route:WalkRoute(steps:steps,distance:total,destinationID:"connection:"+edge.id,destinationCoordinate:connection.coordinate,excludedSegmentIDs:blocked)))
        }
        return (seeds,direct)
    }

    private func bestRoute(seeds:[SearchSeed],direct:[DestinationRoute],connections:[DestinationConnection],blocked:Set<String>)->DestinationRoute? {
        let usable=connections.filter { edgeByID[$0.edgeID] != nil && !blocked.contains($0.edgeID) }
        guard !usable.isEmpty else { return nil }
        var targetNodes=Set<String>()
        for connection in usable {
            guard let edge=edgeByID[connection.edgeID] else { continue }
            if edge.direction != "backward" { targetNodes.insert(edge.from) }
            if edge.direction != "forward" { targetNodes.insert(edge.to) }
        }
        var costs:[String:Double]=[:],previous:[String:RouteStep]=[:],prefixes:[String:[RouteStep]]=[:],visited=Set<String>(),heap=MinHeap()
        for seed in seeds where nodeIDs.contains(seed.node) && seed.cost<costs[seed.node,default:.infinity] {
            costs[seed.node]=seed.cost;prefixes[seed.node]=seed.prefix;previous[seed.node]=nil;heap.push(seed.cost,seed.node)
        }
        var remaining=targetNodes
        while let (cost,current)=heap.pop() {
            if visited.contains(current) { continue }
            visited.insert(current);remaining.remove(current)
            if remaining.isEmpty { break }
            for index in adjacency[current] ?? [] {
                let edge=network.edges[index]
                guard !blocked.contains(edge.id) else { continue }
                var step:RouteStep?
                if edge.from==current && edge.direction != "backward" { step=RouteStep(id:edge.id,from:edge.from,to:edge.to,distance:edge.distance,shape:edge.shape) }
                else if edge.to==current && edge.direction != "forward" { step=RouteStep(id:edge.id,from:edge.to,to:edge.from,distance:edge.distance,shape:Array(edge.shape.reversed())) }
                if let step,!visited.contains(step.to),cost+step.distance<costs[step.to,default:.infinity] {
                    costs[step.to]=cost+step.distance;previous[step.to]=step;heap.push(cost+step.distance,step.to)
                }
            }
        }
        var bestEndpoint:ScoredEndpoint?
        for connection in usable {
            guard let edge=edgeByID[connection.edgeID] else { continue }
            let destinationFraction=min(1,max(0,connection.fraction))
            for (node,startFraction,allowed) in [(edge.from,0.0,edge.direction != "backward"),(edge.to,1.0,edge.direction != "forward")] where allowed {
                guard let cost=costs[node] else { continue }
                let routeDistance=cost+abs(destinationFraction-startFraction)*edge.distance
                let candidate=ScoredEndpoint(connection:connection,node:node,fraction:startFraction,routeDistance:routeDistance,score:routeDistance+connection.distance)
                if better(candidate.score,candidate.connection,than:bestEndpoint?.score,bestEndpoint?.connection) { bestEndpoint=candidate }
            }
        }
        let bestDirect=direct.min { lhs,rhs in
            let left=lhs.route.distance+lhs.connection.distance,right=rhs.route.distance+rhs.connection.distance
            return left==right ? connectionOrder(lhs.connection,rhs.connection):left<right
        }
        let directScore=bestDirect.map { $0.route.distance+$0.connection.distance }
        if let bestDirect,better(directScore!,bestDirect.connection,than:bestEndpoint?.score,bestEndpoint?.connection) { return bestDirect }
        guard let endpoint=bestEndpoint,let edge=edgeByID[endpoint.connection.edgeID] else { return bestDirect }
        var reversed:[RouteStep]=[],cursor=endpoint.node
        while let step=previous[cursor] { reversed.append(step);cursor=step.from }
        var steps=prefixes[cursor] ?? []
        steps.append(contentsOf:reversed.reversed())
        let destinationFraction=min(1,max(0,endpoint.connection.fraction)),distance=abs(destinationFraction-endpoint.fraction)*edge.distance
        if distance>0.1 { steps.append(RouteStep(id:edge.id,from:endpoint.node,to:"destination",distance:distance,shape:Geometry.slice(edge.shape,from:endpoint.fraction,to:destinationFraction))) }
        let route=WalkRoute(steps:steps,distance:endpoint.routeDistance,destinationID:"connection:"+edge.id,destinationCoordinate:endpoint.connection.coordinate,excludedSegmentIDs:blocked)
        return DestinationRoute(connection:endpoint.connection,route:route)
    }

    private func better(_ score:Double,_ connection:DestinationConnection,than otherScore:Double?,_ other:DestinationConnection?)->Bool {
        guard let otherScore,let other else { return true }
        if score != otherScore { return score<otherScore }
        return connectionOrder(connection,other)
    }
    private func connectionOrder(_ lhs:DestinationConnection,_ rhs:DestinationConnection)->Bool {
        lhs.distance==rhs.distance ? lhs.edgeID<rhs.edgeID:lhs.distance<rhs.distance
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
        guard let next,next.shape.count>=2 else { return coreLocalized("まっすぐ。") }
        let incoming=Geometry.bearing(current.shape[current.shape.count-2],current.shape.last!),outgoing=Geometry.bearing(next.shape[0],next.shape[1])
        let angle=(outgoing-incoming+540).truncatingRemainder(dividingBy:360)-180
        if abs(angle)<25 { return coreLocalized("次の角もまっすぐ。") }
        if abs(angle)>150 { return coreLocalized("次の角で折り返し。") }
        return coreLocalized("次の角で{0}へ。",coreLocalized(angle>0 ? "右":"左"))
    }
}
/// `offRoad`: inside the region and accurate enough, but no road within the match radius (distance to the closest road).
public enum LocationVerdict: Sendable { case matched(String), uncertain(String), outside, offRoad(Double) }
public enum PositionGate {
    public static func evaluate(_ p: LocationSample, network: Network, now: Date = Date()) -> LocationVerdict {
        guard p.accuracy >= 0, p.accuracy <= 35 else { return .uncertain("位置の精度が不足しています。空が見える場所で位置の更新を待っています。") }
        let age=now.timeIntervalSince(p.timestamp)
        guard age >= -2, age <= 30 else { return .uncertain("位置情報が更新されていません。新しい位置を待っています。") }
        guard network.bounds.contains(p.coordinate) else { return .outside }
        let options = RoadMatcher(network: network).candidates(at:p.coordinate,radius:max(10,p.accuracy))
        guard let first = options.first else {
            let closest = network.edges.map { Geometry.project(p.coordinate, onto: $0.shape).distance }.min()
            return closest.map { .offRoad($0) } ?? .uncertain("位置に対応する歩行区間がありません。")
        }
        let competitive=options.dropFirst().prefix { $0.distance-first.distance < max(5,p.accuracy) }
        if competitive.contains(where: { !sameJunction(first.id,$0.id,position:p.coordinate,tolerance:max(5,p.accuracy),network:network) }) {
            return .uncertain("道路候補が複数あります。方向案内を保留します。")
        }
        return .matched(first.id)
    }
    /// Adjacent segments meeting under the receiver at one junction describe the same
    /// usable start point. Parallel roads and overpasses remain ambiguous.
    private static func sameJunction(_ lhs:String,_ rhs:String,position:Coordinate,tolerance:Double,network:Network)->Bool {
        guard let a=network.edge(lhs),let b=network.edge(rhs),a.layer == b.layer else { return false }
        let shared=Set([a.from,a.to]).intersection([b.from,b.to])
        return shared.contains { id in network.place(id).map { position.distance(to:$0.coordinate) <= tolerance } ?? false }
    }
}
public struct PositionResolver: Sendable {
    private var networkKey:String?
    private var candidate:String?
    private var count=0
    private var lastSample:LocationSample?
    public init() {}
    public mutating func reset() { networkKey=nil;candidate=nil;count=0;lastSample=nil }
    public mutating func evaluate(_ sample:LocationSample,network:Network,now:Date=Date())->LocationVerdict {
        let key=network.id+"/"+network.version
        if networkKey != key { reset();networkKey=key }
        let verdict=PositionGate.evaluate(sample,network:network,now:now)
        guard case .matched(let id)=verdict else { candidate=nil;count=0;return verdict }
        if let previous=lastSample,previous.timestamp != sample.timestamp {
            let elapsed=sample.timestamp.timeIntervalSince(previous.timestamp)
            guard elapsed>0,previous.simulated==sample.simulated,sample.coordinate.distance(to:previous.coordinate)<=max(15,elapsed*4+previous.accuracy+sample.accuracy) else { reset();return .uncertain("位置の移動が不連続です。道路との対応を再確認します。") }
        }
        if candidate != id { candidate=id;count=0 }
        if lastSample?.timestamp != sample.timestamp { count += 1;lastSample=sample }
        return count>=3 ? .matched(id):.uncertain("")
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
