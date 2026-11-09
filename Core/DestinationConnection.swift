import Foundation

public struct DestinationConnection: Identifiable, Sendable {
    public var edgeID:String
    public var coordinate:Coordinate
    public var distance:Double
    public var fraction:Double
    public var id:String { edgeID }
    // Resolve the destination's road before minimizing the journey distance.
    // A farther road is not an alternative entrance: scoring its straight-line gap
    // against a road detour would let the search cut through buildings or blocks.
    // Keep coincident projections at junctions (within one metre) so each legal
    // direction can still be searched, but never move the endpoint to avoid a closure.
    public static func candidates(for coordinate:Coordinate,network:Network,limit:Int=5)->[Self] {
        guard coordinate.latitude.isFinite,coordinate.longitude.isFinite,network.bounds.contains(coordinate) else { return [] }
        let projected:[Self]=network.edges.compactMap { edge in
            let projection=Geometry.project(coordinate,onto:edge.shape)
            guard projection.distance.isFinite,projection.fraction.isFinite else { return nil }
            return Self(edgeID:edge.id,coordinate:projection.coordinate,distance:projection.distance,fraction:projection.fraction)
        }.sorted { $0.distance == $1.distance ? $0.edgeID<$1.edgeID:$0.distance<$1.distance }
        guard let nearest=projected.first else { return [] }
        return projected.filter {
            $0.distance <= nearest.distance+1 && $0.coordinate.distance(to:nearest.coordinate) <= 1
        }.prefix(max(0,limit)).map { $0 }
    }
}
