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
    /// The part of a polyline between two normalized positions, preserving intermediate vertices and direction.
    public static func slice(_ shape:[Coordinate],from startFraction:Double,to endFraction:Double)->[Coordinate] {
        guard shape.count>1 else { return shape }
        let total=length(shape)
        guard total>0,total.isFinite else { return [shape[0]] }
        let start=min(1,max(0,startFraction)),end=min(1,max(0,endFraction))
        if start>end { return Array(slice(shape,from:end,to:start).reversed()) }
        let startDistance=start*total,endDistance=end*total
        var result=[point(along:shape,at:startDistance).coordinate],walked=0.0
        for (index,segment) in zip(shape,shape.dropFirst()).enumerated() {
            walked += segment.0.distance(to:segment.1)
            if index+1 < shape.count-1,walked>startDistance,walked<endDistance { result.append(shape[index+1]) }
        }
        let last=point(along:shape,at:endDistance).coordinate
        if result.last != last { result.append(last) }
        return result
    }
    /// Intersections in a local metre projection, including endpoint touches and overlaps.
    static func intersections(_ a:Coordinate,_ b:Coordinate,_ c:Coordinate,_ d:Coordinate)->[Coordinate] {
        let margin=0.000001
        guard max(min(a.latitude,b.latitude),min(c.latitude,d.latitude)) <= min(max(a.latitude,b.latitude),max(c.latitude,d.latitude))+margin,
              max(min(a.longitude,b.longitude),min(c.longitude,d.longitude)) <= min(max(a.longitude,b.longitude),max(c.longitude,d.longitude))+margin else { return [] }
        let sy=111_195.0,sx=sy*cos(a.latitude * .pi/180)
        let rx=(b.longitude-a.longitude)*sx,ry=(b.latitude-a.latitude)*sy
        let cx=(c.longitude-a.longitude)*sx,cy=(c.latitude-a.latitude)*sy
        let dx=(d.longitude-c.longitude)*sx,dy=(d.latitude-c.latitude)*sy
        let length=rx*rx+ry*ry
        if length<1e-12 { return project(a,onto:[c,d]).distance<0.01 ? [a]:[] }
        let denominator=rx*dy-ry*dx
        func point(_ t:Double)->Coordinate { Coordinate(a.latitude+(b.latitude-a.latitude)*t,a.longitude+(b.longitude-a.longitude)*t) }
        if abs(denominator)>1e-10 {
            let t=(cx*dy-cy*dx)/denominator,u=(cx*ry-cy*rx)/denominator
            guard t >= -1e-9,t <= 1+1e-9,u >= -1e-9,u <= 1+1e-9 else { return [] }
            return [point(min(1,max(0,t)))]
        }
        guard abs(cx*ry-cy*rx)/sqrt(length)<0.01 else { return [] }
        let t0=(cx*rx+cy*ry)/length,t1=((cx+dx)*rx+(cy+dy)*ry)/length
        let lower=max(0,min(t0,t1)),upper=min(1,max(t0,t1))
        guard lower <= upper+1e-9 else { return [] }
        return [point(min(1,max(0,lower))),point(min(1,max(0,(lower+upper)/2))),point(min(1,max(0,upper)))]
    }

}
public struct MatchCandidate: Identifiable, Sendable { public var id: String; public var distance: Double }
public struct RoadSelectionResult: Sendable { public var edgeIDs: [String]; public var candidates: [MatchCandidate]; public var ambiguous: Bool; public var message: String }
public struct RoadMatcher: Sendable {
    public var network: Network
    public init(network: Network) { self.network = network }
    public func candidates(at p: Coordinate, radius: Double) -> [MatchCandidate] {
        network.edges.compactMap { edge in
            let d = Geometry.project(p, onto: edge.shape).distance
            return d <= radius ? MatchCandidate(id: edge.id, distance: d) : nil
        }.sorted { $0.distance < $1.distance }
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
    public func tap(_ point:Coordinate,radius:Double)->RoadSelectionResult {
        guard point.latitude.isFinite,point.longitude.isFinite,network.bounds.contains(point) else { return RoadSelectionResult(edgeIDs:[],candidates:[],ambiguous:false,message:"対応範囲外です。登録する道路を選択できません。") }
        let options=candidates(at:point,radius:radius)
        guard let first=options.first else { return RoadSelectionResult(edgeIDs:[],candidates:[],ambiguous:false,message:"タップした場所に対応する道路データがありません。") }
        let ambiguous=options.count>1 && options[1].distance-first.distance<max(3,radius*0.35)
        return RoadSelectionResult(edgeIDs:ambiguous ? []:[first.id],candidates:ambiguous ? Array(options.prefix(5)):[],ambiguous:ambiguous,message:ambiguous ? "近くに複数の道路があります。対象を確認してください。":"タップした道路区間全体を選択しました。")
    }
}
