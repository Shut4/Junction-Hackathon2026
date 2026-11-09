import XCTest
@testable import GuideCore

final class BlockedCrossingTests:XCTestCase {
    private func network(detour:Bool=true,split:Bool=true,layer:String="0")->Network {
        func point(_ x:Double,_ y:Double)->Coordinate { Coordinate(33.883+y*0.001,130.88+x*0.001) }
        let nodes=[Place(id:"a",name:"A",coordinate:point(-1,0)),Place(id:"j",name:"J",coordinate:point(0,0)),Place(id:"b",name:"B",coordinate:point(1,0)),Place(id:"c",name:"C",coordinate:point(0,-1)),Place(id:"d",name:"D",coordinate:point(0,1)),Place(id:"x",name:"X",coordinate:point(-1,2)),Place(id:"y",name:"Y",coordinate:point(1,2))]
        func edge(_ id:String,_ from:Int,_ to:Int,_ roadLayer:String="0")->WalkEdge {
            let shape=[nodes[from].coordinate,nodes[to].coordinate]
            return WalkEdge(id:id,name:id,from:nodes[from].id,to:nodes[to].id,shape:shape,distance:Geometry.length(shape),direction:"both",conditions:"test",sourceID:"test",verification:"test",layer:roadLayer,kind:"footway")
        }
        var edges=[edge("closed",3,4)]
        edges += split ? [edge("aj",0,1,layer),edge("jb",1,2,layer)]:[edge("ab",0,2,layer)]
        if detour { edges += [edge("ax",0,5),edge("xy",5,6),edge("yb",6,2)] }
        return Network(id:"crossing",name:"Test",version:"1",bounds:Bounds(south:33.87,west:130.87,north:33.90,east:130.90),source:"test",acquiredAt:"test",isSimulated:true,nodes:nodes,edges:edges,destinations:[])
    }
    func testSharedJunctionUsesDetourAndPreservesOriginalReportCount() throws {
        let n=network(),router=Router(network:n)
        XCTAssertEqual(router.route(from:"a",to:"b",blocked:[])?.steps.map(\.id),["aj","jb"])
        let route=try XCTUnwrap(router.route(from:"a",to:"b",blocked:["closed"]))
        XCTAssertEqual(route.steps.map(\.id),["ax","xy","yb"])
        XCTAssertEqual(route.excludedSegmentIDs,["closed"])
        XCTAssertTrue(router.allows(route,blocked:["closed"]))
        let unsafe=try XCTUnwrap(router.route(from:"a",to:"b",blocked:[]))
        XCTAssertFalse(router.allows(unsafe,blocked:["closed"]))
        // Reusing the same router after removing a report must restore the short route.
        XCTAssertEqual(router.route(from:"a",to:"b",blocked:[])?.steps.count,2)
    }
    func testCrossingWithoutSharedNodeAndCollinearOverlapAreRejected() {
        var n=network(detour:false,split:false)
        XCTAssertNil(Router(network:n).route(from:"a",to:"b",blocked:["closed"]))
        n.edges[1].shape=n.edges[0].shape;n.edges[1].from="c";n.edges[1].to="d"
        XCTAssertNil(Router(network:n).route(from:"c",to:"d",blocked:["closed"]))
    }
    func testExplicitGradeSeparationIsKeptButUnknownLayerIsNotAssumedSafe() {
        XCTAssertNotNil(Router(network:network(detour:false,split:false,layer:"1")).route(from:"a",to:"b",blocked:["closed"]))
        XCTAssertNil(Router(network:network(detour:false,split:false,layer:"未記載")).route(from:"a",to:"b",blocked:["closed"]))
    }
    func testPointAndBatchedDestinationRoutesCannotTraverseClosedJunction() throws {
        let n=network(detour:false),router=Router(network:n)
        let start=Coordinate(33.883,130.8795)
        let end=DestinationConnection(edgeID:"jb",coordinate:Coordinate(33.883,130.8805),distance:0,fraction:0.5)
        XCTAssertEqual(router.resolveRoute(from:start,on:"aj",to:end,blocked:["closed"]).crossingFailure,.noRoute)
        XCTAssertEqual(router.bestRoute(from:start,on:"aj",to:[end],blocked:["closed"]).crossingFailure,.noRoute)
        XCTAssertNil(router.bestRoute(from:"a",to:[end],blocked:["closed"]))
        // Stopping before the barrier or leaving from a blocked junction is not a crossing.
        let before=DestinationConnection(edgeID:"aj",coordinate:start,distance:0,fraction:0.5)
        XCTAssertNotNil(router.route(from:"a",to:before,blocked:["closed"]))
        XCTAssertNotNil(router.route(from:"j",to:"a",blocked:["closed"]))
    }
    func testDestinationGapCannotSuggestCrossingARegisteredBarrier() {
        let n=network(),router=Router(network:n)
        XCTAssertFalse(router.allowsConnector(from:n.nodes[0].coordinate,to:n.nodes[2].coordinate,blocked:["closed"]))
        XCTAssertTrue(router.allowsConnector(from:n.nodes[5].coordinate,to:n.nodes[6].coordinate,blocked:["closed"]))
        XCTAssertTrue(router.allowsConnector(from:n.nodes[0].coordinate,to:n.nodes[2].coordinate,blocked:[]))
    }
    func testUnblockedEntryRoadCannotBeReachedAcrossBarrier() {
        var n=network(detour:false,split:false)
        var right=n.edges[1]
        right.id="right";right.from="b";right.to="y";right.shape=[n.nodes[2].coordinate,n.nodes[6].coordinate];right.distance=Geometry.length(right.shape)
        n.edges=[n.edges[0],right]
        let router=Router(network:n),start=n.nodes[0].coordinate
        let destination=DestinationConnection(edgeID:"right",coordinate:Coordinate(33.884,130.881),distance:0,fraction:0.5)
        XCTAssertEqual(router.resolveOffRoadRoute(from:start,to:"y",blocked:["closed"]).crossingFailure,.noRoute)
        XCTAssertEqual(router.resolveOffRoadRoute(from:start,to:destination,blocked:["closed"]).crossingFailure,.noRoute)
        XCTAssertEqual(router.bestOffRoadRoute(from:start,to:[destination],blocked:["closed"]).crossingFailure,.noRoute)
    }
    func testOffRoadApproachesCannotCrossAClosure() {
        let n=network(detour:false,split:false),router=Router(network:n)
        let start=Coordinate(33.883,130.8795)
        let end=DestinationConnection(edgeID:"ab",coordinate:Coordinate(33.883,130.8805),distance:0,fraction:0.75)
        XCTAssertEqual(router.resolveOffRoadRoute(from:start,to:"b",blocked:["closed"]).crossingFailure,.noRoute)
        XCTAssertEqual(router.resolveOffRoadRoute(from:start,to:end,blocked:["closed"]).crossingFailure,.blockedDestination)
        XCTAssertEqual(router.bestOffRoadRoute(from:start,to:[end],blocked:["closed"]).crossingFailure,.blockedDestination)
    }
}

private extension Result where Failure==RouteFailure {
    var crossingFailure:RouteFailure? { if case .failure(let error)=self { return error };return nil }
}
