import XCTest
@testable import GuideCore

final class CoreTests:XCTestCase {
    func testRoadTapSelectsRealEdgeAndDoesNotGuessAtJunction() {
        let n=fixture(),matcher=RoadMatcher(network:n)
        let middle=Coordinate(33.883,130.8805)
        XCTAssertEqual(matcher.tap(middle,radius:15).edgeIDs,["ab"])
        let junction=matcher.tap(n.nodes[0].coordinate,radius:15)
        XCTAssertTrue(junction.ambiguous);XCTAssertTrue(junction.edgeIDs.isEmpty);XCTAssertGreaterThan(junction.candidates.count,1)
        XCTAssertTrue(matcher.tap(Coordinate(34,131),radius:15).edgeIDs.isEmpty)
        XCTAssertTrue(matcher.tap(Coordinate(33.888,130.888),radius:15).edgeIDs.isEmpty)
    }
    func testDestinationConnectionsRequireCoverageAndExplicitCandidates() {
        let n=fixture()
        XCTAssertEqual(DestinationConnection.candidates(for:n.nodes[0].coordinate,network:n).first?.nodeID,"a")
        XCTAssertTrue(DestinationConnection.candidates(for:Coordinate(35.0,139.0),network:n).isEmpty)
        XCTAssertTrue(DestinationConnection.candidates(for:Coordinate(.nan,130.88),network:n).isEmpty)
        XCTAssertTrue(DestinationConnection.candidates(for:Coordinate(33.888,130.888),network:n).isEmpty)
        var disconnected=n;disconnected.nodes.append(Place(id:"orphan",name:"入口未接続",coordinate:Coordinate(33.883,130.88001)))
        XCTAssertFalse(DestinationConnection.candidates(for:disconnected.nodes.last!.coordinate,network:disconnected).contains { $0.nodeID=="orphan" })
    }
    func testSpeechPriorityDuplicatesRouteInvalidationAndStop() {
        var q=SpeechQueue();let now=Date()
        XCTAssertTrue(q.enqueue("old route",obstacle:false,now:now))
        XCTAssertFalse(q.enqueue("old route",obstacle:false,now:now))
        q.enqueue("obstacle",obstacle:true,now:now);XCTAssertEqual(q.next(now:now)?.text,"obstacle")
        q.invalidateRoute();XCTAssertNil(q.next(now:now))
        q.enqueue("new route",obstacle:false,now:now);q.stop();XCTAssertNil(q.next(now:now))
    }
    func testExpiredObstacleIsNotSpokenAndEqualPriorityIsStable() {
        var q=SpeechQueue();let now=Date()
        q.enqueue("one",obstacle:true,now:now);q.enqueue("two",obstacle:true,now:now)
        XCTAssertEqual(q.next(now:now)?.text,"one");XCTAssertNil(q.next(now:now.addingTimeInterval(3)))
    }
    func testTurnDirectionRequiresReliableMovingCourse() throws {
        let n=fixture(),r=try XCTUnwrap(Router(network:n).route(from:"a",to:"c",blocked:["ad"]))
        let p=LocationSample(coordinate:Coordinate(33.883,130.8805),accuracy:3,timestamp:Date(),course:90,courseAccuracy:5,speed:1)
        XCTAssertTrue(TurnGuidance.instruction(current:r.steps[0],next:r.steps[1],sample:p)?.contains("左") == true)
        var uncertain=p;uncertain.speed=0;XCTAssertNil(TurnGuidance.instruction(current:r.steps[0],next:r.steps[1],sample:uncertain))
        uncertain=p;uncertain.course=270;XCTAssertNil(TurnGuidance.instruction(current:r.steps[0],next:r.steps[1],sample:uncertain))
    }
    func fixture() -> Network {
        let nodes=[Place(id:"a",name:"A",coordinate:Coordinate(33.883,130.88)),Place(id:"b",name:"B",coordinate:Coordinate(33.883,130.881)),Place(id:"c",name:"C",coordinate:Coordinate(33.884,130.881)),Place(id:"d",name:"D",coordinate:Coordinate(33.884,130.88))]
        func edge(_ id:String,_ a:Int,_ b:Int,_ direction:String="both") -> WalkEdge { WalkEdge(id:id,name:id,from:nodes[a].id,to:nodes[b].id,shape:[nodes[a].coordinate,nodes[b].coordinate],distance:nodes[a].coordinate.distance(to:nodes[b].coordinate),direction:direction,conditions:"test",sourceID:"test",verification:"test",layer:"0",kind:"footway") }
        return Network(id:"test",version:"1",bounds:Bounds(south:33.88,west:130.87,north:33.89,east:130.89),source:"test",acquiredAt:"test",isSimulated:true,nodes:nodes,edges:[edge("ab",0,1),edge("bc",1,2),edge("ad",0,3),edge("dc",3,2)],destinations:[Destination(id:"c",name:"C",nodeID:"c",note:"test")])
    }
    func testBlockedEdgeDetourAndAllClosed() throws {
        let n=fixture(),router=Router(network:n)
        let route=try XCTUnwrap(router.route(from:"a",to:"c",blocked:["ab"]))
        XCTAssertEqual(route.steps.map(\.id),["ad","dc"])
        XCTAssertNil(router.route(from:"a",to:"c",blocked:["ab","ad"]))
    }
    func testWalkingOneWay() {
        var n=fixture();n.edges=[n.edges[0]];n.edges[0].direction="forward"
        XCTAssertNotNil(Router(network:n).route(from:"a",to:"b",blocked:[]))
        XCTAssertNil(Router(network:n).route(from:"b",to:"a",blocked:[]))
    }
    func testPositionStartsAtProjectionAndCannotEscapeBlockedEdge() throws {
        let n=fixture();let a=n.nodes[0].coordinate,b=n.nodes[1].coordinate
        let p=Coordinate(a.latitude,(a.longitude+b.longitude)/2)
        let r=try XCTUnwrap(Router(network:n).route(from:p,on:"ab",to:"b",blocked:[]))
        XCTAssertEqual(r.distance,n.edges[0].distance/2,accuracy:0.1)
        XCTAssertEqual(r.steps.first?.shape.first?.longitude,p.longitude)
        XCTAssertNil(Router(network:n).route(from:p,on:"ab",to:"c",blocked:["ab"]))
    }
    func testConnectedSelectionRejectsDisconnected() {
        let matcher=RoadMatcher(network:fixture())
        XCTAssertTrue(matcher.connected(["ab","bc"]))
        XCTAssertFalse(matcher.connected(["ab","dc"]))
        XCTAssertFalse(matcher.connected([]))
    }
    func testTraceSelectsRoadShapeNotFreehand() {
        let n=fixture(),result=RoadMatcher(network:n).trace([Coordinate(33.88301,130.8802),Coordinate(33.88301,130.8808)],radius:8)
        XCTAssertEqual(result.edgeIDs,["ab"]);XCTAssertFalse(result.ambiguous)
    }
    func testTraceOutsideAndMissingRoad() {
        let m=RoadMatcher(network:fixture())
        XCTAssertTrue(m.trace([Coordinate(34,130),Coordinate(34,130.1)],radius:8).edgeIDs.isEmpty)
        XCTAssertTrue(m.trace([Coordinate(33.887,130.887),Coordinate(33.887,130.888)],radius:5).edgeIDs.isEmpty)
    }
    func testParallelAndOverpassRemainAmbiguous() {
        var n=fixture();var parallel=n.edges[0];parallel.id="parallel";parallel.layer="1";parallel.shape=parallel.shape.map { Coordinate($0.latitude+0.00001,$0.longitude) };n.edges.append(parallel)
        let result=RoadMatcher(network:n).trace([Coordinate(33.883005,130.8802),Coordinate(33.883005,130.8808)],radius:8)
        XCTAssertTrue(result.ambiguous);XCTAssertEqual(Set(result.candidates.map(\.id)),["ab","parallel"])
        if case .uncertain = PositionGate.evaluate(LocationSample(coordinate:Coordinate(33.883005,130.8805),accuracy:3,timestamp:Date()),network:n) {} else { XCTFail("Parallel roads must not be resolved by nearest edge") }
    }
    func testPositionAgeAccuracyAndRange() {
        let n=fixture(),p=Coordinate(33.883,130.8805),now=Date()
        for s in [LocationSample(coordinate:p,accuracy:-1,timestamp:now),LocationSample(coordinate:p,accuracy:30,timestamp:now),LocationSample(coordinate:p,accuracy:3,timestamp:now.addingTimeInterval(-9)),LocationSample(coordinate:p,accuracy:3,timestamp:now.addingTimeInterval(10))] { if case .uncertain = PositionGate.evaluate(s,network:n,now:now) {} else { XCTFail() } }
        if case .outside = PositionGate.evaluate(LocationSample(coordinate:Coordinate(34,131),accuracy:3,timestamp:now),network:n,now:now) {} else { XCTFail() }
        if case .matched("ab") = PositionGate.evaluate(LocationSample(coordinate:p,accuracy:3,timestamp:now),network:n,now:now) {} else { XCTFail() }
    }
    func testPositionResolverRequiresDistinctRecentSamplesAndRejectsTeleportation() {
        let n=fixture(),now=Date();var resolver=PositionResolver()
        let p=Coordinate(33.883,130.8805)
        for i in 0..<2 { if case .uncertain=resolver.evaluate(LocationSample(coordinate:p,accuracy:3,timestamp:now.addingTimeInterval(Double(i))),network:n,now:now.addingTimeInterval(Double(i))) {} else { XCTFail() } }
        if case .uncertain=resolver.evaluate(LocationSample(coordinate:p,accuracy:3,timestamp:now.addingTimeInterval(1)),network:n,now:now.addingTimeInterval(1)) {} else { XCTFail("same location timestamp must not increase evidence") }
        if case .matched=resolver.evaluate(LocationSample(coordinate:p,accuracy:3,timestamp:now.addingTimeInterval(2)),network:n,now:now.addingTimeInterval(2)) {} else { XCTFail() }
        if case .uncertain=resolver.evaluate(LocationSample(coordinate:Coordinate(33.884,130.8805),accuracy:3,timestamp:now.addingTimeInterval(3)),network:n,now:now.addingTimeInterval(3)) {} else { XCTFail("jump must hold guidance") }
    }
    func store() -> ReportStore { ReportStore(url:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("reports.json")) }
    func testPersistenceRestartBatchAndExactlyFiveReportFields() throws {
        let s=store(),n=fixture(),reports=[Report(segmentID:"ab",hazard:.flood,observedAt:Date(),explanation:"test"),Report(segmentID:"bc",hazard:.debris,observedAt:Date(),explanation:"test")]
        try s.save(reports,network:n)
        XCTAssertEqual(try ReportStore(url:s.url).load(network:n).map(\.id),reports.map(\.id))
        let json=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:s.url)) as? [String:Any]),items=try XCTUnwrap(json["reports"] as? [[String:Any]])
        XCTAssertEqual(Set(items[0].keys),["id","segmentID","hazard","observedAt","explanation"])
    }
    func testFailedBatchPreservesPreviousData() throws {
        let s=store(),n=fixture(),first=Report(segmentID:"ab",hazard:.other,observedAt:Date(),explanation:nil)
        try s.save([first],network:n);s.failWrite=true
        XCTAssertThrowsError(try s.save([first,Report(segmentID:"bc",hazard:.flood,observedAt:Date(),explanation:nil)],network:n))
        XCTAssertEqual(try s.load(network:n).count,1)
    }
    func testCorruptionVersionAndUnknownEdgeFailClosed() throws {
        let s=store(),n=fixture();try s.save([Report(segmentID:"ab",hazard:.other,observedAt:Date(),explanation:nil)],network:n)
        var next=n;next.version="2";XCTAssertThrowsError(try s.load(network:next))
        next=n;next.edges.removeFirst();XCTAssertThrowsError(try s.load(network:next))
        try Data("invalid".utf8).write(to:s.url);XCTAssertThrowsError(try s.load(network:n))
    }
    func testNoAutomaticReportExpiry() throws {
        let s=store(),n=fixture();try s.save([Report(segmentID:"ab",hazard:.other,observedAt:Date(timeIntervalSince1970:0),explanation:nil)],network:n);XCTAssertEqual(try s.load(network:n).count,1)
    }
    func detection(_ label:String="pole",_ time:Double=0,_ x:Double=0.3) -> Detection { Detection(label:label,confidence:0.9,box:Box(x:x,y:0.3,width:0.2,height:0.4),capturedAt:time) }
    func testPersistenceChatterAndReappearance() {
        var f=NoticeFilter()
        XCTAssertTrue(f.process([detection()],now:0).isEmpty)
        XCTAssertEqual(f.process([detection("pole",0.7)],now:0.7).count,1)
        XCTAssertTrue(f.process([detection("pole",1)],now:1).isEmpty)
        _=f.process([],now:10)
        XCTAssertTrue(f.process([detection("pole",10)],now:10).isEmpty)
        XCTAssertEqual(f.process([detection("pole",10.7)],now:10.7).count,1)
        XCTAssertEqual(f.notices,2);XCTAssertGreaterThan(f.suppressed,0)
    }
    func testClassCooldownSurvivesTrackerChurnAndMultipleTargets() {
        var f=NoticeFilter();_=f.process([detection()],now:0);_=f.process([detection("pole",0.7)],now:0.7)
        _=f.process([detection("pole",1,0.7),detection("stairs",1)],now:1)
        let notices=f.process([detection("pole",1.7,0.7),detection("stairs",1.7)],now:1.7)
        XCTAssertEqual(notices.map(\.label),["stairs"])
    }
    func testOldLowConfidenceUnsupportedAndReset() {
        var f=NoticeFilter();var low=detection();low.confidence=0.2
        XCTAssertTrue(f.process([low,detection("flood"),detection("pole",0)],now:2).isEmpty)
        _=f.process([detection("pole",3)],now:3);f.reset()
        XCTAssertTrue(f.process([detection("pole",3.7)],now:3.7).isEmpty)
    }
    func testBundledRealNetworkIntegrityAndDetours() throws {
        let url=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Data/kokura-network.json")
        let n=try JSONDecoder().decode(Network.self,from:Data(contentsOf:url));try n.validate();XCTAssertFalse(n.isSimulated)
        let start=try XCTUnwrap(n.destinations.first?.nodeID),end=try XCTUnwrap(n.destinations.last?.nodeID)
        let router=Router(network:n),base=try XCTUnwrap(router.route(from:start,to:end,blocked:[]));XCTAssertFalse(base.steps.isEmpty)
        var found=false
        for step in base.steps { if let alternate=router.route(from:start,to:end,blocked:[step.id]) { XCTAssertFalse(alternate.steps.contains { $0.id==step.id });found=true;break } }
        XCTAssertTrue(found,"At least one actual segment closure must permit a detour")
        XCTAssertNil(router.route(from:start,to:end,blocked:Set(n.edges.map(\.id))))
    }
    func testManeuverAndProgressAlongRoute() throws {
        let n=fixture(),route=try XCTUnwrap(Router(network:n).route(from:"a",to:"c",blocked:["ad"]))
        XCTAssertEqual(Maneuver.between(route.steps[0],route.steps[1]),.left)
        XCTAssertEqual(Maneuver.between(route.steps[1],nil),.arrive)
        let start=n.nodes[0].coordinate,p=try XCTUnwrap(RouteTracker.progress(route:route,stepIndex:0,position:start,lookahead:15))
        XCTAssertEqual(p.remainingDistance,route.distance,accuracy:0.5)
        XCTAssertEqual(p.distanceToStepEnd,route.steps[0].distance,accuracy:0.5)
        XCTAssertEqual(start.distance(to:p.lookahead),15,accuracy:0.5)
        let nearEnd=Geometry.point(along:route.steps[0].shape,at:route.steps[0].distance-5).coordinate
        let turning=try XCTUnwrap(RouteTracker.progress(route:route,stepIndex:0,position:nearEnd,lookahead:15))
        XCTAssertEqual(turning.lookahead.distance(to:n.nodes[1].coordinate),10,accuracy:0.5,"lookahead continues into the next step")
        XCTAssertEqual(RouteTracker.relativeBearing(from:start,to:n.nodes[1].coordinate,heading:0),90,accuracy:1)
        XCTAssertEqual(RouteTracker.relativeBearing(from:start,to:n.nodes[1].coordinate,heading:180),-90,accuracy:1)
        XCTAssertEqual(Geometry.length(RouteTracker.shape(of:route)),route.distance,accuracy:0.5)
    }
    func testDebugLogCapacityFilterAndPersistence() throws {
        var log=DebugLogBuffer(capacity:3)
        for i in 0..<5 { log.append(DebugLogEntry(category:i.isMultiple(of:2) ? .route:.camera,level:i==4 ? .error:.info,title:"event \(i)",fields:[LogField("key","value\(i)")],operationID:"op\(i)",source:"x",function:"y")) }
        XCTAssertEqual(log.entries.map(\.title),["event 2","event 3","event 4"]);XCTAssertEqual(log.dropped,2)
        XCTAssertEqual(log.filtered(category:.route).map(\.title),["event 4","event 2"],"newest first")
        XCTAssertEqual(log.filtered(level:.error).count,1);XCTAssertEqual(log.filtered(query:"value3").count,1);XCTAssertEqual(log.filtered(query:"OP4").count,1)
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("log.json")
        try log.save(to:url);let restored=try XCTUnwrap(DebugLogBuffer.load(from:url,capacity:2))
        XCTAssertEqual(restored.entries.map(\.title),["event 3","event 4"]);XCTAssertEqual(restored.entries.last?.date.timeIntervalSince1970 ?? 0,log.entries.last!.date.timeIntervalSince1970,accuracy:0.001)
        log.clear();XCTAssertTrue(log.entries.isEmpty)
        XCTAssertNil(DebugLogBuffer.load(from:url.appendingPathExtension("missing"),capacity:2))
    }
    func testExplicitReportMigrationKeepsMatchingIDsAndArchiveNeverDeletes() throws {
        let s=store(),n=fixture();try s.save([Report(segmentID:"ab",hazard:.other,observedAt:Date(),explanation:nil),Report(segmentID:"bc",hazard:.flood,observedAt:Date(),explanation:nil)],network:n)
        var next=n;next.version="2";next.edges.removeAll { $0.id=="bc" }
        XCTAssertThrowsError(try s.load(network:next),"version change still fails closed")
        let preview=try s.migrationPreview(network:next);XCTAssertEqual(preview.kept.map(\.segmentID),["ab"]);XCTAssertEqual(preview.dropped.map(\.segmentID),["bc"])
        let backup=try XCTUnwrap(try s.archive(label:"v1"));XCTAssertTrue(FileManager.default.fileExists(atPath:backup.path));XCTAssertFalse(FileManager.default.fileExists(atPath:s.url.path))
        try s.save(preview.kept,network:next);XCTAssertEqual(try s.load(network:next).count,1)
    }
}
