import Foundation
public struct Projection: Sendable { public var distance: Double; public var fraction: Double; public var coordinate: Coordinate; public var bearing: Double }
public enum Geometry {
    public static func bearing(_ a: Coordinate, _ b: Coordinate) -> Double {
        let r = Double.pi / 180, x = (b.longitude-a.longitude)*r
        return (atan2(sin(x)*cos(b.latitude*r), cos(a.latitude*r)*sin(b.latitude*r)-sin(a.latitude*r)*cos(b.latitude*r)*cos(x))*180/Double.pi+360).truncatingRemainder(dividingBy: 360)
    }
    public static func length(_ shape:[Coordinate])->Double { zip(shape,shape.dropFirst()).reduce(0) { $0+$1.0.distance(to:$1.1) } }
    /// Point at `distance` metres along the polyline, clamped to its ends.
    public static func point(along shape:[Coordinate],at distance:Double)->(coordinate:Coordinate,bearing:Double) {
        guard let first=shape.first else { return (Coordinate(0,0),0) }
        guard shape.count>1 else { return (first,0) }
        var remaining=max(0,distance)
        for (a,b) in zip(shape,shape.dropFirst()) {
            let length=a.distance(to:b)
            if remaining<=length && length>0 { let t=remaining/length;return (Coordinate(a.latitude+(b.latitude-a.latitude)*t,a.longitude+(b.longitude-a.longitude)*t),bearing(a,b)) }
            remaining -= length
        }
        return (shape.last!,bearing(shape[shape.count-2],shape.last!))
    }
    public static func project(_ p: Coordinate, onto shape: [Coordinate]) -> Projection {
        var best = Projection(distance: .infinity, fraction: 0, coordinate: p, bearing: 0)
        let total = zip(shape, shape.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }; var walked = 0.0
        for (a,b) in zip(shape, shape.dropFirst()) {
            let sy = 111_195.0, sx = sy*cos(p.latitude * .pi/180)
            let ax = (a.longitude-p.longitude)*sx, ay = (a.latitude-p.latitude)*sy
            let dx = (b.longitude-a.longitude)*sx, dy = (b.latitude-a.latitude)*sy
            let length = a.distance(to: b), denominator = dx*dx+dy*dy
            let t = denominator > 0 ? min(1,max(0,-(ax*dx+ay*dy)/denominator)) : 0
            let distance = hypot(ax+t*dx,ay+t*dy)
            if distance < best.distance { best = Projection(distance: distance, fraction: total > 0 ? (walked+t*length)/total : 0, coordinate: Coordinate(a.latitude+(b.latitude-a.latitude)*t,a.longitude+(b.longitude-a.longitude)*t), bearing: bearing(a,b)) }
            walked += length
        }
        return best
    }
}
public struct MatchCandidate: Identifiable, Sendable { public var id: String; public var distance: Double; public var score: Double }
public struct TraceResult: Sendable { public var edgeIDs: [String]; public var candidates: [MatchCandidate]; public var ambiguous: Bool; public var message: String }
public struct RoadMatcher: Sendable {
    public var network: Network
    public init(network: Network) { self.network = network }
    public func candidates(at p: Coordinate, radius: Double) -> [MatchCandidate] {
        network.edges.compactMap { edge in
            let d = Geometry.project(p, onto: edge.shape).distance
            return d <= radius ? MatchCandidate(id: edge.id, distance: d, score: d) : nil
        }.sorted { $0.score < $1.score }
    }
    public func connected(_ ids: Set<String>) -> Bool {
        guard let first = ids.first else { return false }
        let chosen = network.edges.filter { ids.contains($0.id) }
        let byID = Dictionary(chosen.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen: Set<String> = [first], queue = [first]
        while let id = queue.popLast(), let e = byID[id] {
            for other in chosen where !seen.contains(other.id) && (other.from == e.from || other.from == e.to || other.to == e.from || other.to == e.to) { seen.insert(other.id); queue.append(other.id) }
        }
        return seen == ids
    }
    public func tap(_ point:Coordinate,radius:Double)->TraceResult {
        guard point.latitude.isFinite,point.longitude.isFinite,network.bounds.contains(point) else { return TraceResult(edgeIDs:[],candidates:[],ambiguous:false,message:"対応範囲外です。登録する道路を選択できません。") }
        let options=candidates(at:point,radius:radius)
        guard let first=options.first else { return TraceResult(edgeIDs:[],candidates:[],ambiguous:false,message:"タップした場所に対応する道路データがありません。") }
        let ambiguous=options.count>1 && options[1].distance-first.distance<max(3,radius*0.35)
        return TraceResult(edgeIDs:ambiguous ? []:[first.id],candidates:ambiguous ? Array(options.prefix(5)):[],ambiguous:ambiguous,message:ambiguous ? "近くに複数の道路があります。対象を確認してください。":"タップした道路区間全体を選択しました。")
    }
    public func trace(_ points: [Coordinate], radius: Double) -> TraceResult {
        guard points.count >= 2, points.allSatisfy(network.bounds.contains) else { return TraceResult(edgeIDs: [], candidates: [], ambiguous: false, message: "対応範囲内の道路をなぞってください。") }
        var selected: [String] = [], ambiguous = false, alternatives: [String: MatchCandidate] = [:]
        for i in points.indices {
            var options = candidates(at: points[i], radius: radius)
            if i > 0 && points[i-1].distance(to: points[i]) > 2 {
                let heading = Geometry.bearing(points[i-1], points[i])
                for j in options.indices {
                    guard let e = network.edge(options[j].id) else { continue }
                    let bearing = Geometry.project(points[i], onto: e.shape).bearing
                    let diff = abs(heading-bearing).truncatingRemainder(dividingBy: 180)
                    options[j].score += min(diff,180-diff)/90 * radius * 0.6
                }
            }
            if let last = selected.last, let previous = network.edge(last) {
                for j in options.indices where options[j].id != last {
                    if let e = network.edge(options[j].id), ![previous.from, previous.to].contains(e.from), ![previous.from, previous.to].contains(e.to) { options[j].score += radius*2 }
                }
            }
            options.sort { $0.score < $1.score }
            guard let first = options.first else { return TraceResult(edgeIDs: [], candidates: [], ambiguous: false, message: "道路データに照合できない部分があります。範囲を縮めてやり直してください。") }
            if options.count > 1 && options[1].score-first.score < max(3,radius*0.35) { ambiguous = true; for c in options.prefix(3) { alternatives[c.id] = c } }
            if selected.last != first.id { selected.append(first.id) }
        }
        let unique = Array(Set(selected)).sorted()
        guard connected(Set(unique)) else { return TraceResult(edgeIDs: [], candidates: Array(alternatives.values), ambiguous: true, message: "区間が連続しません。候補を一覧で確認してください。") }
        return TraceResult(edgeIDs: unique, candidates: alternatives.values.sorted { $0.distance < $1.distance }, ambiguous: ambiguous, message: ambiguous ? "候補が曖昧です。選択対象を一覧で確認してください。" : "道路区間全体を選択しました。保存前に両端を確認してください。")
    }
}
