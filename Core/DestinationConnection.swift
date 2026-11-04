import Foundation

public struct DestinationConnection: Identifiable, Sendable {
    public var edgeID:String
    public var coordinate:Coordinate
    public var distance:Double
    public var fraction:Double
    public var id:String { edgeID }
    // Candidates are saved-road endpoints for explicit confirmation, never proof of an accessible entrance.
    // There is deliberately no fixed radius: every finite point inside the advertised region can select the
    // nearest saved road, while the UI keeps the unverified gap visible and separate from the guided route.
    public static func candidates(for coordinate:Coordinate,network:Network,limit:Int=5)->[Self] {
        guard coordinate.latitude.isFinite,coordinate.longitude.isFinite,network.bounds.contains(coordinate) else { return [] }
        return network.edges.compactMap { edge in
            let projection=Geometry.project(coordinate,onto:edge.shape)
            guard projection.distance.isFinite,projection.fraction.isFinite else { return nil }
            return Self(edgeID:edge.id,coordinate:projection.coordinate,distance:projection.distance,fraction:projection.fraction)
        }.sorted { $0.distance == $1.distance ? $0.edgeID<$1.edgeID:$0.distance<$1.distance }.prefix(max(0,limit)).map { $0 }
    }
}
