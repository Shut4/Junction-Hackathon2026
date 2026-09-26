import Foundation

public struct DestinationConnection: Identifiable, Sendable {
    public var nodeID:String
    public var distance:Double
    public var id:String { nodeID }
    // Candidates are suggestions for explicit confirmation, never proof of an accessible entrance.
    public static func candidates(for coordinate:Coordinate,network:Network,radius:Double=40)->[Self] {
        guard coordinate.latitude.isFinite,coordinate.longitude.isFinite,network.bounds.contains(coordinate) else { return [] }
        let connected=Set(network.edges.flatMap { [$0.from,$0.to] })
        return network.nodes.filter { connected.contains($0.id) }.compactMap { node in
            let distance=node.coordinate.distance(to:coordinate)
            return distance<=radius ? Self(nodeID:node.id,distance:distance):nil
        }.sorted { $0.distance == $1.distance ? $0.nodeID<$1.nodeID:$0.distance<$1.distance }
    }
}
