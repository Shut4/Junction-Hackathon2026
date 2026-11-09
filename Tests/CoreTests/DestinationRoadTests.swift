import XCTest
@testable import GuideCore

final class DestinationRoadTests:XCTestCase {
    private func network()->Network {
        let coordinates=[Coordinate(33.883,130.880),Coordinate(33.886,130.880),Coordinate(33.886,130.881),Coordinate(33.883,130.881)]
        let nodes=zip(["a","b","c","d"],coordinates).map { Place(id:$0.0,name:$0.0,coordinate:$0.1) }
        let edges=[(0,1),(1,2),(2,3)].map { from,to in
            WalkEdge(id:nodes[from].id+nodes[to].id,name:"road",from:nodes[from].id,to:nodes[to].id,shape:[coordinates[from],coordinates[to]],distance:coordinates[from].distance(to:coordinates[to]),direction:"both",conditions:"test",sourceID:"test",verification:"test",layer:"0",kind:"footway")
        }
        return Network(id:"detour",name:"detour",version:"1",bounds:Bounds(south:33.88,west:130.87,north:33.89,east:130.89),source:"test",acquiredAt:"test",isSimulated:true,nodes:nodes,edges:edges,destinations:[])
    }
    func testDestinationCannotBeReplacedWithDistantRoadToShortenJourney() throws {
        let n=network(),router=Router(network:n),target=n.nodes[3].coordinate
        let connections=DestinationConnection.candidates(for:target,network:n,limit:12)
        XCTAssertEqual(connections.map(\.edgeID),["cd"])
        let found=try XCTUnwrap(router.bestRoute(from:"a",to:connections,blocked:[]))
        XCTAssertEqual(found.route.steps.map(\.id),["ab","bc","cd"])
        XCTAssertEqual(found.route.destinationCoordinate,target)
        XCTAssertEqual(found.connection.distance,0,accuracy:0.01)
        XCTAssertGreaterThan(found.route.distance,n.nodes[0].coordinate.distance(to:target)*5)
    }
    func testBlockedOrDisconnectedDestinationHasNoDistantFallback() {
        var n=network()
        let connections=DestinationConnection.candidates(for:n.nodes[3].coordinate,network:n,limit:12)
        XCTAssertNil(Router(network:n).bestRoute(from:"a",to:connections,blocked:["cd"]))
        n.edges.removeAll { $0.id=="bc" }
        XCTAssertNil(Router(network:n).bestRoute(from:"a",to:connections,blocked:[]))
    }
    func testRealPositionAndOffRoadStartStillReachDestinationRoad() throws {
        let n=network(),router=Router(network:n)
        let connections=DestinationConnection.candidates(for:n.nodes[3].coordinate,network:n,limit:12)
        let matched=try router.bestRoute(from:n.nodes[0].coordinate,on:"ab",to:connections,blocked:[]).get()
        XCTAssertEqual(matched.route.steps.last?.id,"cd")
        let offRoad=Coordinate(33.8831,130.8799)
        let approached=try router.bestOffRoadRoute(from:offRoad,to:connections,blocked:[]).get()
        XCTAssertTrue(approached.route.steps.first?.isApproach == true)
        XCTAssertEqual(approached.route.steps.last?.id,"cd")
        XCTAssertEqual(approached.route.destinationCoordinate,n.nodes[3].coordinate)
    }
    func testSoocanaUsesNearestRoadRatherThanStraightLineShortcut() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let n=try JSONDecoder().decode(Network.self,from:Data(contentsOf:root.appendingPathComponent("Data/tobata-network.json")))
        // Apple Maps search result for ソオカナ; entrance accessibility remains unverified.
        let target=Coordinate(33.8961473,130.8410268),start=Coordinate(33.8949,130.8414)
        let connections=DestinationConnection.candidates(for:target,network:n,limit:12)
        let nearest=try XCTUnwrap(n.edges.map { Geometry.project(target,onto:$0.shape).distance }.min())
        let startEdge=try XCTUnwrap(n.edges.min { Geometry.project(start,onto:$0.shape).distance < Geometry.project(start,onto:$1.shape).distance })
        let found=try Router(network:n).bestRoute(from:start,on:startEdge.id,to:connections,blocked:[]).get()
        XCTAssertLessThanOrEqual(found.connection.distance,nearest+1)
        XCTAssertLessThan(found.connection.distance,25,"Do not stop 87m before the destination")
        let legacy=n.edges.map { edge -> DestinationConnection in
            let p=Geometry.project(target,onto:edge.shape)
            return DestinationConnection(edgeID:edge.id,coordinate:p.coordinate,distance:p.distance,fraction:p.fraction)
        }.sorted { $0.distance<$1.distance }.prefix(12)
        let shortcut=try Router(network:n).bestRoute(from:start,on:startEdge.id,to:Array(legacy),blocked:[]).get()
        XCTAssertGreaterThan(shortcut.connection.distance,found.connection.distance+30)
        XCTAssertEqual(found.route.steps.last?.shape.last,found.connection.coordinate)
        XCTAssertTrue(found.route.steps.allSatisfy { step in n.edges.contains { $0.id==step.id } })
    }
    func testCoincidentJunctionConnectionsRetainLegalAlternatives() {
        let n=network()
        let connections=DestinationConnection.candidates(for:n.nodes[1].coordinate,network:n,limit:12)
        XCTAssertEqual(Set(connections.map(\.edgeID)),["ab","bc"])
        XCTAssertNotNil(Router(network:n).bestRoute(from:"a",to:connections,blocked:[]))
    }
}
