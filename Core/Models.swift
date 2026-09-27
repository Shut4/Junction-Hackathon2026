import Foundation

public func coreLocalized(_ key:String,_ arguments:Any...) -> String {
    var text=Bundle.main.localizedString(forKey:key,value:key,table:nil)
    for (index,argument) in arguments.enumerated() {
        text=text.replacingOccurrences(of:"{\(index)}",with:String(describing:argument))
    }
    return text
}

public struct Coordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(_ latitude: Double, _ longitude: Double) { self.latitude = latitude; self.longitude = longitude }
    public func distance(to other: Self) -> Double {
        let r = Double.pi / 180
        let a = pow(sin((other.latitude - latitude) * r / 2), 2) + cos(latitude * r) * cos(other.latitude * r) * pow(sin((other.longitude - longitude) * r / 2), 2)
        return 6_371_000 * 2 * atan2(sqrt(a), sqrt(max(0, 1-a)))
    }
}
public struct Place: Codable, Identifiable, Sendable {
    public var id: String; public var name: String; public var coordinate: Coordinate
}
public struct WalkEdge: Codable, Identifiable, Sendable {
    public var id: String; public var name: String; public var from: String; public var to: String
    public var shape: [Coordinate]; public var distance: Double; public var direction: String
    public var conditions: String; public var sourceID: String; public var verification: String
    public var layer: String; public var kind: String
}
public struct Destination: Codable, Identifiable, Sendable {
    public var id: String; public var name: String; public var nodeID: String; public var note: String
}
public struct Bounds: Codable, Sendable {
    public var south: Double; public var west: Double; public var north: Double; public var east: Double
    public func contains(_ c: Coordinate) -> Bool { (south...north).contains(c.latitude) && (west...east).contains(c.longitude) }
}
public struct Network: Codable, Sendable {
    public var id: String; public var name: String; public var version: String; public var bounds: Bounds
    public var source: String; public var acquiredAt: String; public var isSimulated: Bool
    public var nodes: [Place]; public var edges: [WalkEdge]; public var destinations: [Destination]
    public func validate() throws {
        let ids = Set(nodes.map(\.id)), es = Set(edges.map(\.id))
        guard !nodes.isEmpty, ids.count == nodes.count, es.count == edges.count else { throw CoreError.invalidNetwork }
        guard edges.allSatisfy({ ids.contains($0.from) && ids.contains($0.to) && $0.shape.count >= 2 && $0.distance > 0 && $0.distance.isFinite && ["both", "forward", "backward"].contains($0.direction) && $0.shape.allSatisfy({ $0.latitude.isFinite && $0.longitude.isFinite && abs($0.latitude) <= 90 && abs($0.longitude) <= 180 }) }), destinations.allSatisfy({ ids.contains($0.nodeID) }) else { throw CoreError.invalidNetwork }
    }
    public func place(_ id: String) -> Place? { nodes.first { $0.id == id } }
    public func edge(_ id: String) -> WalkEdge? { edges.first { $0.id == id } }
}
public enum NetworkCatalog {
    public static func containing(_ coordinate: Coordinate, in networks: [Network]) -> Network? { networks.first { $0.bounds.contains(coordinate) } }
    public static func canRoute(from start: Coordinate, to destination: Coordinate, in network: Network) -> Bool { network.bounds.contains(start) && network.bounds.contains(destination) }
}
public enum Hazard: String, Codable, CaseIterable, Sendable { case debris = "瓦礫", flood = "冠水", collapse = "崩壊", other = "その他" }
public struct Report: Codable, Identifiable, Sendable {
    public var id: UUID; public var segmentID: String; public var hazard: Hazard; public var observedAt: Date; public var explanation: String?
    public init(segmentID: String, hazard: Hazard, observedAt: Date, explanation: String?) {
        id = UUID(); self.segmentID = segmentID; self.hazard = hazard; self.observedAt = observedAt; self.explanation = explanation
    }
    enum CodingKeys:String,CodingKey { case id,segmentID,hazard,observedAt,explanation }
    public func encode(to encoder:any Encoder) throws {
        var c=encoder.container(keyedBy:CodingKeys.self)
        try c.encode(id,forKey:.id);try c.encode(segmentID,forKey:.segmentID);try c.encode(hazard,forKey:.hazard);try c.encode(observedAt,forKey:.observedAt)
        if let explanation { try c.encode(explanation,forKey:.explanation) } else { try c.encodeNil(forKey:.explanation) }
    }
}
public enum CoreError: Error, LocalizedError { case invalidNetwork, incompatibleReports, corruptReports, disconnectedSelection
    public var errorDescription: String? { switch self {
    case .invalidNetwork: return coreLocalized("道路データに不整合があります。案内を開始できません。")
    case .incompatibleReports: return coreLocalized("道路データの版と報告が一致しません。報告を保持して案内を保留します。")
    case .corruptReports: return coreLocalized("報告を読み込めません。報告なしとは扱いません。")
    case .disconnectedSelection: return coreLocalized("離れた区間が含まれています。連続する区間を選んでください。")
    } }
}
