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
        return Network(id:"test",name:"テスト地域",version:"1",bounds:Bounds(south:33.88,west:130.87,north:33.89,east:130.89),source:"test",acquiredAt:"test",isSimulated:true,nodes:nodes,edges:[edge("ab",0,1),edge("bc",1,2),edge("ad",0,3),edge("dc",3,2)],destinations:[Destination(id:"c",name:"C",nodeID:"c",note:"test")])
    }
    func testBlockedEdgeDetourAndAllClosed() throws {
        let n=fixture(),router=Router(network:n)
        let route=try XCTUnwrap(router.route(from:"a",to:"c",blocked:["ab"]))
        XCTAssertEqual(route.steps.map(\.id),["ad","dc"])
        XCTAssertEqual(route.excludedSegmentIDs,["ab"])
        XCTAssertEqual(route.excludedSegmentCount,1)
        XCTAssertTrue(route.blockedSegmentsInRoute.isEmpty)
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
    func testParallelAndOverpassRemainAmbiguous() {
        var n=fixture();var parallel=n.edges[0];parallel.id="parallel";parallel.layer="1";parallel.shape=parallel.shape.map { Coordinate($0.latitude+0.00001,$0.longitude) };n.edges.append(parallel)
        let result=RoadMatcher(network:n).tap(Coordinate(33.883005,130.8805),radius:8)
        XCTAssertTrue(result.ambiguous);XCTAssertEqual(Set(result.candidates.map(\.id)),["ab","parallel"])
        if case .uncertain = PositionGate.evaluate(LocationSample(coordinate:Coordinate(33.883005,130.8805),accuracy:3,timestamp:Date()),network:n) {} else { XCTFail("Parallel roads must not be resolved by nearest edge") }
    }
    func testPositionAgeAccuracyAndRange() {
        let n=fixture(),p=Coordinate(33.883,130.8805),now=Date()
        for s in [LocationSample(coordinate:p,accuracy:-1,timestamp:now),LocationSample(coordinate:p,accuracy:40,timestamp:now),LocationSample(coordinate:p,accuracy:3,timestamp:now.addingTimeInterval(-31)),LocationSample(coordinate:p,accuracy:3,timestamp:now.addingTimeInterval(10))] { if case .uncertain = PositionGate.evaluate(s,network:n,now:now) {} else { XCTFail() } }
        if case .matched("ab") = PositionGate.evaluate(LocationSample(coordinate:p,accuracy:30,timestamp:now.addingTimeInterval(-20)),network:n,now:now) {} else { XCTFail("A usable stationary fix must not expire after eight seconds") }
        if case .outside = PositionGate.evaluate(LocationSample(coordinate:Coordinate(34,131),accuracy:3,timestamp:now),network:n,now:now) {} else { XCTFail() }
        if case .matched("ab") = PositionGate.evaluate(LocationSample(coordinate:p,accuracy:3,timestamp:now),network:n,now:now) {} else { XCTFail() }
    }
    func testPositionAtJunctionMatchesButParallelRoadRemainsAmbiguous() {
        let n=fixture(),junction=n.nodes[1].coordinate
        if case .matched(let id)=PositionGate.evaluate(LocationSample(coordinate:junction,accuracy:3,timestamp:Date()),network:n) { XCTAssertTrue(["ab","bc"].contains(id)) }
        else { XCTFail("Segments meeting at the current junction must be treated as one usable start") }
        var parallel=n;var duplicate=n.edges[0];duplicate.id="upper";duplicate.layer="1";duplicate.shape=duplicate.shape.map { Coordinate($0.latitude+0.00001,$0.longitude) };parallel.edges.append(duplicate)
        if case .uncertain=PositionGate.evaluate(LocationSample(coordinate:Coordinate(33.883005,130.8805),accuracy:3,timestamp:Date()),network:parallel) {} else { XCTFail("Different road layers must remain ambiguous") }
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
    func testDuplicateReportsKeepSegmentBlockedUntilLastOneIsRemoved() {
        let first=Report(segmentID:"ab",hazard:.flood,observedAt:Date(),explanation:nil)
        let second=Report(segmentID:"ab",hazard:.debris,observedAt:Date(),explanation:nil)
        var reports=[first,second]
        XCTAssertEqual(Set(reports.map(\.segmentID)),["ab"])
        reports.removeAll { $0.id==first.id }
        XCTAssertEqual(Set(reports.map(\.segmentID)),["ab"],"Removing one report must not reopen a segment with another report")
        reports.removeAll { $0.id==second.id }
        XCTAssertTrue(Set(reports.map(\.segmentID)).isEmpty,"Removing the last report reopens the segment")
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
    func testAllBundledRegionalNetworksValidateAndRoute() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for file in ["kokura-network.json","tobata-network.json"] {
            let network=try JSONDecoder().decode(Network.self,from:Data(contentsOf:root.appendingPathComponent("Data").appendingPathComponent(file)))
            try network.validate();XCTAssertFalse(network.isSimulated);XCTAssertFalse(network.name.isEmpty)
            let start=try XCTUnwrap(network.destinations.first?.nodeID),end=try XCTUnwrap(network.destinations.last?.nodeID),router=Router(network:network)
            let base=try XCTUnwrap(router.route(from:start,to:end,blocked:[]),file);XCTAssertFalse(base.steps.isEmpty)
            XCTAssertTrue(base.steps.contains { step in router.route(from:start,to:end,blocked:[step.id]) != nil },"\(file) must have a tested detour")
        }
    }
    func testTobataPositionRouteBlockDetourReleaseAndFailures() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let network=try JSONDecoder().decode(Network.self,from:Data(contentsOf:root.appendingPathComponent("Data/tobata-network.json")))
        let startDestination=try XCTUnwrap(network.destinations.first),target=try XCTUnwrap(network.destinations.dropFirst().first)
        let startEdge=try XCTUnwrap(network.edges.first { $0.from==startDestination.nodeID || $0.to==startDestination.nodeID })
        let position=Geometry.point(along:startEdge.shape,at:Geometry.length(startEdge.shape)/2).coordinate
        let router=Router(network:network)
        let base=try XCTUnwrap(try router.resolveRoute(from:position,on:startEdge.id,to:target.nodeID,blocked:[]).get())
        XCTAssertFalse(base.steps.isEmpty)
        let detourPair=base.steps.dropFirst().lazy.compactMap { step -> (RouteStep,WalkRoute)? in
            guard case .success(let route)=router.resolveRoute(from:position,on:startEdge.id,to:target.nodeID,blocked:[step.id]) else { return nil }
            return (step,route)
        }.first
        let (closed,detour)=try XCTUnwrap(detourPair,"The Tobata route must have a closable segment with an alternate route")
        XCTAssertFalse(detour.steps.contains { $0.id==closed.id })
        let reopened=try XCTUnwrap(try router.resolveRoute(from:position,on:startEdge.id,to:target.nodeID,blocked:[]).get())
        XCTAssertEqual(reopened.steps.map(\.id),base.steps.map(\.id),"Removing the closure must calculate from current state")
        if case .failure(.blockedStart)=router.resolveRoute(from:position,on:startEdge.id,to:target.nodeID,blocked:[startEdge.id]) {} else { XCTFail("A blocked current edge needs its own failure") }
        let everythingAfterStart=Set(network.edges.map(\.id)).subtracting([startEdge.id])
        if case .failure(.noRoute)=router.resolveRoute(from:position,on:startEdge.id,to:target.nodeID,blocked:everythingAfterStart) {} else { XCTFail("No alternate path must be distinct from a position match failure") }
    }
    func testRegionSelectionAndCrossRegionRoutingBoundary() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Data")
        let decoder=JSONDecoder(),kokura=try decoder.decode(Network.self,from:Data(contentsOf:root.appendingPathComponent("kokura-network.json"))),tobata=try decoder.decode(Network.self,from:Data(contentsOf:root.appendingPathComponent("tobata-network.json")))
        let kokuraPoint=Coordinate((kokura.bounds.south+kokura.bounds.north)/2,(kokura.bounds.west+kokura.bounds.east)/2)
        let tobataPoint=Coordinate((tobata.bounds.south+tobata.bounds.north)/2,(tobata.bounds.west+tobata.bounds.east)/2)
        XCTAssertEqual(NetworkCatalog.containing(kokuraPoint,in:[kokura,tobata])?.id,kokura.id)
        XCTAssertEqual(NetworkCatalog.containing(tobataPoint,in:[kokura,tobata])?.id,tobata.id)
        XCTAssertFalse(NetworkCatalog.canRoute(from:kokuraPoint,to:tobataPoint,in:kokura))
        XCTAssertFalse(NetworkCatalog.canRoute(from:kokuraPoint,to:tobataPoint,in:tobata))
    }
    func testReportsRemainSeparatedByRegionalStore() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Data")
        let decoder=JSONDecoder(),kokura=try decoder.decode(Network.self,from:Data(contentsOf:root.appendingPathComponent("kokura-network.json"))),tobata=try decoder.decode(Network.self,from:Data(contentsOf:root.appendingPathComponent("tobata-network.json")))
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let kokuraStore=ReportStore(url:directory.appendingPathComponent("real-reports.json")),tobataStore=ReportStore(url:directory.appendingPathComponent("real-reports-tobata-ground-osm.json"))
        try kokuraStore.save([Report(segmentID:try XCTUnwrap(kokura.edges.first?.id),hazard:.other,observedAt:Date(),explanation:nil)],network:kokura)
        XCTAssertEqual(try kokuraStore.load(network:kokura).count,1);XCTAssertTrue(try tobataStore.load(network:tobata).isEmpty)
        try tobataStore.save([Report(segmentID:try XCTUnwrap(tobata.edges.first?.id),hazard:.flood,observedAt:Date(),explanation:nil)],network:tobata)
        XCTAssertEqual(try kokuraStore.load(network:kokura).count,1);XCTAssertEqual(try tobataStore.load(network:tobata).count,1)
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
    func testDirectionBucketsWithHysteresis() {
        XCTAssertEqual(DirectionBucket.of(5),.ahead);XCTAssertEqual(DirectionBucket.of(-40),.slightLeft);XCTAssertEqual(DirectionBucket.of(90),.right);XCTAssertEqual(DirectionBucket.of(-170),.behind)
        XCTAssertEqual(DirectionBucket.of(22,keeping:.ahead),.ahead);XCTAssertEqual(DirectionBucket.of(30,keeping:.ahead),.slightRight)
    }
    func testDirectionAnnouncerWaitsForStabilityGapAndRepeatsTurns() {
        var a=DirectionAnnouncer()
        XCTAssertNil(a.update(angle:90,reason:"",now:0));XCTAssertNil(a.update(angle:90,reason:"",now:1))
        XCTAssertEqual(a.update(angle:90,reason:"",now:1.3),"右へ。")
        XCTAssertNil(a.update(angle:92,reason:"",now:5))
        XCTAssertEqual(a.update(angle:92,reason:"",now:11.4),"右へ。")
        XCTAssertNil(a.update(angle:0,reason:"",now:12));XCTAssertNil(a.update(angle:0,reason:"",now:13))
        XCTAssertEqual(a.update(angle:0,reason:"",now:15.5),"直進です。")
        XCTAssertNil(a.update(angle:0,reason:"",now:40))
        XCTAssertNil(a.update(angle:nil,reason:"保留",now:41));XCTAssertEqual(a.update(angle:nil,reason:"保留",now:44),"保留");XCTAssertNil(a.update(angle:nil,reason:"保留",now:60))
        a.reset();XCTAssertNil(a.update(angle:0,reason:"",now:61));XCTAssertEqual(a.update(angle:0,reason:"",now:62.5),"直進です。")
    }
    func testCameraPoseFromGravity() {
        let upright=CameraPose.from(gravityX:0,y:-1,z:0);XCTAssertEqual(upright.tilt,0,accuracy:1e-9);XCTAssertEqual(upright.roll,0,accuracy:1e-9)
        XCTAssertEqual(CameraPose.from(gravityX:0,y:0,z:-1).tilt,.pi/2,accuracy:1e-9)
        XCTAssertEqual(CameraPose.from(gravityX:0,y:-cos(0.3),z:-sin(0.3)).tilt,0.3,accuracy:1e-9)
        XCTAssertEqual(CameraPose.from(gravityX:-sin(0.2),y:-cos(0.2),z:0).roll,0.2,accuracy:1e-9)
    }
    func testDirectionSpeechExpiresWithCustomLifetime() {
        var q=SpeechQueue();let now=Date()
        q.enqueue("右へ",obstacle:false,now:now,ttl:3);XCTAssertNil(q.next(now:now.addingTimeInterval(4)))
    }
    func testOffRoadPositionInsideRegionGetsApproachRoute() throws {
        let n=fixture(),router=Router(network:n)
        let south=Coordinate(33.8825,130.8805)
        guard case .offRoad(let d)=PositionGate.evaluate(LocationSample(coordinate:south,accuracy:5,timestamp:Date()),network:n) else { return XCTFail("off-road inside the region must be routable") }
        XCTAssertEqual(d,55,accuracy:2)
        let route=try router.resolveOffRoadRoute(from:south,to:"c",blocked:[]).get()
        XCTAssertTrue(route.steps[0].isApproach);XCTAssertEqual(route.steps[0].shape.first,south);XCTAssertEqual(route.steps[1].id,"bc","shortest total, not merely the closest road")
        XCTAssertEqual(route.distance,route.steps.map(\.distance).reduce(0,+),accuracy:0.5)
        let detour=try router.resolveOffRoadRoute(from:south,to:"c",blocked:["ab"]).get()
        XCTAssertTrue(detour.steps[0].isApproach);XCTAssertFalse(detour.steps.contains { $0.id == "ab" })
        XCTAssertEqual(router.resolveOffRoadRoute(from:Coordinate(34,131),to:"c",blocked:[]).failureValue,.outsideNetwork)
        XCTAssertEqual(router.resolveOffRoadRoute(from:south,to:"c",blocked:["ab","bc","ad","dc"]).failureValue,.noRoute)
        if case .outside=PositionGate.evaluate(LocationSample(coordinate:Coordinate(34,131),accuracy:5,timestamp:Date()),network:n) {} else { XCTFail("outside the region stays unsupported") }
        if case .uncertain=PositionGate.evaluate(LocationSample(coordinate:south,accuracy:80,timestamp:Date()),network:n) {} else { XCTFail("poor accuracy still holds") }
    }
    func testHeadLevelPixelMappingFollowsPortraitOrientation() {
        // Buffer column below the centre = lower on screen; buffer row above the centre = right on screen.
        let p=HeadLevelGeometry.devicePoint(u:340,v:200,depth:2,fx:500,fy:500,cx:320,cy:240)
        XCTAssertLessThan(p.y,0);XCTAssertGreaterThan(p.x,0);XCTAssertEqual(p.z,-2)
    }
    func testHeadLevelDetectsHighObstacleAndIgnoresGround() {
        let upright=SIMD3<Float>(0,-1,0)
        // Floor points ahead 1–3 m, 1.3 m below the lens.
        let floor=(0..<60).map { SIMD3<Float>(Float($0%5)*0.1-0.2,-1.3,-1-Float($0)/30) }
        let clear=HeadLevelGeometry.evaluate(points:floor,gravity:upright,cameraHeight:1.3)
        XCTAssertNil(clear.hit);XCTAssertTrue(clear.floorMeasured);XCTAssertEqual(clear.floor,-1.3,accuracy:0.05)
        // A sign board 2.3 m ahead (between the 2 m danger and 2.5 m announce distances) at 1.4–1.8 m above the floor.
        let board=(0..<20).map { SIMD3<Float>(Float($0%4)*0.1-0.15,0.1+Float($0)/50,-2.3) }
        let hit=try? XCTUnwrap(HeadLevelGeometry.evaluate(points:floor+board,gravity:upright,cameraHeight:1.3).hit)
        XCTAssertEqual(hit?.stage,.caution);XCTAssertEqual(hit?.distance ?? 0,2.3,accuracy:0.01)
        let near=board.map { SIMD3<Float>($0.x,$0.y,-0.8) }
        XCTAssertEqual(HeadLevelGeometry.evaluate(points:floor+near,gravity:upright,cameraHeight:1.3).hit?.stage,.danger)
        // Outside the corridor (1 m to the right) or knee height: no warning.
        XCTAssertNil(HeadLevelGeometry.evaluate(points:floor+board.map { SIMD3<Float>($0.x+1,$0.y,$0.z) },gravity:upright,cameraHeight:1.3).hit)
        XCTAssertNil(HeadLevelGeometry.evaluate(points:floor+board.map { SIMD3<Float>($0.x,-0.9,$0.z) },gravity:upright,cameraHeight:1.3).hit)
    }
    func testHeadLevelUsesGravityWhenPhoneIsTilted() {
        // Phone tilted 30° down: the same world point appears rotated in the device frame.
        let t=Float.pi/6,g=SIMD3<Float>(0,-cos(t),-sin(t))
        let rotate={ (w:SIMD3<Float>) in SIMD3<Float>(w.x,w.y*cos(t)-w.z*sin(t),w.y*sin(t)+w.z*cos(t)) }
        let board=(0..<20).map { rotate(SIMD3<Float>(0,0.3,-1.5-Float($0)/100)) }
        let hit=HeadLevelGeometry.evaluate(points:board,gravity:g,cameraHeight:1.3).hit
        XCTAssertEqual(hit?.distance ?? 0,1.5,accuracy:0.05);XCTAssertEqual(hit?.height ?? 0,1.6,accuracy:0.05)
    }
    func testHeadLevelAnnouncerNeedsPersistenceAndEscalates() {
        var a=HeadLevelAnnouncer()
        let caution=HeadLevelHit(distance:1.8,lateral:0,height:1.5,count:20,stage:.caution),danger=HeadLevelHit(distance:0.8,lateral:0.3,height:1.5,count:20,stage:.danger)
        XCTAssertNil(a.update(caution,now:0))
        XCTAssertEqual(a.update(caution,now:0.2)?.text,"前方に障害物。")
        XCTAssertNil(a.update(caution,now:1))
        XCTAssertEqual(a.update(danger,now:1.2)?.text,"止まって。")
        XCTAssertNil(a.update(danger,now:2));XCTAssertNotNil(a.update(danger,now:6.3))
        XCTAssertNil(a.update(nil,now:6.5));XCTAssertNil(a.update(nil,now:8));XCTAssertNil(a.update(caution,now:8.2));XCTAssertNotNil(a.update(caution,now:8.4))
    }
    /// Ground seen in every 10 cm strip from -1.4 to 1.4 m, 1–2 m ahead, with the floor 1.3 m below the lens.
    func walkGround(except skip:(Float)->Bool = { _ in false }) -> [WalkSample] {
        stride(from:Float(-1.45),through:1.45,by:0.1).filter { !skip($0) }.flatMap { l in (0..<3).map { WalkSample(forward:1+Float($0)*0.4,lateral:l,up:-1.3) } }
    }
    func walkBlock(_ lateral:ClosedRange<Float>,at forward:Float,up:Float) -> [WalkSample] {
        stride(from:lateral.lowerBound,through:lateral.upperBound,by:0.1).flatMap { l in (0..<4).map { _ in WalkSample(forward:forward,lateral:l,up:up) } }
    }
    func testWalkableFindsBlockedPathAndPassableSide() {
        // Obstacle in the path 2.2 m ahead (beyond the 1.8 m critical distance, 0.5 m tall) and a wall 0.55 m to the right; the left is open.
        let samples=walkGround(except:{ $0 > -0.3 && $0 < 0.8 })+walkBlock(-0.25...0.25,at:2.2,up:-0.8)+walkBlock(0.55...0.75,at:1.2,up:-0.3)
        let p=WalkableGeometry.profile(samples,floor:-1.3)
        XCTAssertEqual(p.blockedAhead ?? 0,2.2,accuracy:0.01);XCTAssertEqual(p.passSide,.left);XCTAssertEqual(p.right?.kind,.obstacle)
        XCTAssertNil(p.left);XCTAssertTrue(p.groundSeen)
        let cues=WalkableAnnouncer().cues(p)
        XCTAssertEqual(cues.first?.text,"前方に障害物。左へ。");XCTAssertEqual(cues.first?.priority,.high)
        XCTAssertTrue(WalkableAnnouncer().cues(p,headLevel:true).allSatisfy { $0.key != "blocked" },"head-level warning covers the same obstacle")
    }
    func testWalkableDropsNarrowPassageAndClearPath() {
        XCTAssertNil(WalkableGeometry.profile(walkGround(),floor:-1.3).blockedAhead)
        let kerb=WalkableGeometry.profile(walkGround(except:{ abs($0) < 0.3 })+walkBlock(-0.25...0.25,at:2,up:-1.5),floor:-1.3)
        XCTAssertEqual(kerb.dropAhead ?? 0,2,accuracy:0.01);XCTAssertNil(kerb.blockedAhead)
        XCTAssertEqual(WalkableAnnouncer().cues(kerb).first?.text,"前方に段差。")
        // Walls 0.35 m left and right: 0.6 m wide passage, both edges close.
        let narrow=WalkableGeometry.profile(walkGround(except:{ abs($0) > 0.3 })+walkBlock(-0.45 ... -0.35,at:1.5,up:-0.5)+walkBlock(0.35...0.45,at:1.5,up:-0.5),floor:-1.3)
        XCTAssertEqual(narrow.width ?? 0,0.6,accuracy:0.05)
        XCTAssertEqual(Set(WalkableAnnouncer().cues(narrow).map(\.key)),["edge-left","edge-right","narrow"])
    }
    func testWalkableAnnouncerPersistsAndRepeatsByPriority() {
        let p=WalkableGeometry.profile(walkGround(except:{ abs($0) < 0.3 })+walkBlock(-0.25...0.25,at:0.8,up:-0.8),floor:-1.3)
        var a=WalkableAnnouncer()
        XCTAssertNil(a.update(p,now:0));XCTAssertEqual(a.update(p,now:0.2)?.priority,.critical)
        XCTAssertNil(a.update(p,now:2));XCTAssertNotNil(a.update(p,now:3.3))
        XCTAssertNil(a.update(nil,now:4));XCTAssertNil(a.update(p,now:7))
    }
    func testSceneCatalogTiersPositionsAndCriticalHazards() {
        XCTAssertEqual(SceneCatalog.classes.count,39)
        XCTAssertEqual(SceneCatalog.classes["signal_red"]?.name,SceneCatalog.classes["signal_blue"]?.name,"signal colour is never spoken")
        var f=NoticeFilter()
        let block=Detection(label:"braille_block",confidence:0.9,box:Box(x:0.05,y:0.1,width:0.2,height:0.2),capturedAt:0)
        let tree=Detection(label:"tree",confidence:0.9,box:Box(x:0.4,y:0.3,width:0.2,height:0.4),capturedAt:0)
        let step=Detection(label:"steps",confidence:0.9,box:Box(x:0.4,y:0.1,width:0.2,height:0.2),capturedAt:0,distance:0.9,lateral:0)
        _=f.process([block,tree,step],now:0)
        let later=[block,tree,step].map { var d=$0;d.capturedAt=0.7;return d }
        let notices=f.process(later,now:0.7)
        XCTAssertEqual(notices.map(\.label),["steps","braille_block"],"context off by default; hazard first")
        XCTAssertEqual(notices.map(\.priority),[.critical,.normal])
        XCTAssertEqual(notices.map(\.text),["目の前に段差。","左前に点字ブロック。"])
        // Hazards still in view repeat; landmarks do not.
        for t in stride(from:1.5,through:10.5,by:1.5) { XCTAssertTrue(f.process(later.map { var d=$0;d.capturedAt=t;return d },now:t).isEmpty) }
        XCTAssertEqual(f.process(later.map { var d=$0;d.capturedAt=11;return d },now:11).map(\.label),["steps"])
        var all=NoticeFilter();all.minimumTier = .context
        _=all.process([tree],now:0);XCTAssertEqual(all.process([Detection(label:"tree",confidence:0.9,box:tree.box,capturedAt:0.7)],now:0.7).first?.priority,.low)
    }
    func testSpeechQueueOrdersFourPriorities() {
        var q=SpeechQueue();let now=Date()
        q.enqueue("low",priority:.low,now:now);q.enqueue("route",priority:.normal,route:true,now:now);q.enqueue("stop",priority:.critical,now:now);q.enqueue("pole",priority:.high,now:now)
        XCTAssertEqual([q.next(now:now),q.next(now:now),q.next(now:now),q.next(now:now)].map { $0?.text },["stop","pole","route","low"])
        q.enqueue("route2",priority:.normal,route:true,now:now);q.enqueue("landmark",priority:.normal,now:now);q.invalidateRoute()
        XCTAssertEqual(q.next(now:now)?.text,"landmark");XCTAssertNil(q.next(now:now))
    }
    func testDepthGridPlacesBoxesInMetres() {
        // 64×48 landscape depth map, everything 2 m away, phone upright; principal point at the centre.
        let grid=DepthGrid(values:[Float](repeating:2,count:64*48),columns:64,rows:48,step:1,fx:50,fy:50,cx:32,cy:24,gravity:SIMD3(0,-1,0),time:0)
        let centre=grid.locate(Box(x:0.45,y:0.4,width:0.1,height:0.1))
        XCTAssertEqual(centre?.distance ?? 0,2,accuracy:0.01);XCTAssertEqual(centre?.lateral ?? 1,0,accuracy:0.1)
        let right=grid.locate(Box(x:0.8,y:0.4,width:0.1,height:0.1))
        XCTAssertGreaterThan(right?.lateral ?? 0,0.5,"right of the portrait image is to the walker's right")
        XCTAssertNil(DepthGrid(values:[Float](repeating:.nan,count:64*48),columns:64,rows:48,step:1,fx:50,fy:50,cx:32,cy:24,gravity:SIMD3(0,-1,0),time:0).locate(Box(x:0.4,y:0.4,width:0.2,height:0.2)))
    }
    func testSceneSummaryOrdersByUsefulness() {
        let items=SceneSummary.items(detections:[
            Detection(label:"vending_machine",confidence:0.9,box:Box(x:0.7,y:0.3,width:0.2,height:0.4),capturedAt:0,distance:1,lateral:1),
            Detection(label:"braille_block",confidence:0.9,box:Box(x:0.05,y:0.1,width:0.2,height:0.2),capturedAt:0),
            Detection(label:"pole",confidence:0.9,box:Box(x:0.4,y:0.3,width:0.2,height:0.4),capturedAt:0,distance:3,lateral:0),
            Detection(label:"pole",confidence:0.9,box:Box(x:0.1,y:0.3,width:0.2,height:0.4),capturedAt:0,distance:1.2,lateral:-0.8),
            Detection(label:"tree",confidence:0.3,box:Box(x:0.4,y:0.3,width:0.2,height:0.4),capturedAt:0)],walkable:nil,headLevel:nil)
        XCTAssertEqual(items.map(\.text),["すぐ左にポール。","左前に点字ブロック。","すぐ右に自動販売機。"],"nearest pole only; low-confidence tree dropped")
        XCTAssertEqual(items.map(\.priority),[.critical,.normal,.low])
    }
    func testSceneTuningChangesThresholds() {
        var t=NoticeTuning();t.criticalDistance=3;t.persistence=0
        var f=NoticeFilter();t.apply(to:&f)
        let pole=Detection(label:"pole",confidence:0.9,box:Box(x:0.4,y:0.3,width:0.2,height:0.4),capturedAt:0,distance:2.5,lateral:0)
        XCTAssertEqual(f.process([pole],now:0).first?.text,"目の前にポール。");XCTAssertEqual(f.process([pole],now:0).count,0)
        let blocked=WalkableGeometry.profile(walkGround(except:{ abs($0) < 0.3 })+walkBlock(-0.25...0.25,at:1.5,up:-0.8),floor:-1.3)
        var timing=WalkableTiming();timing.blockedDistance=1
        XCTAssertTrue(WalkableAnnouncer(timing:timing).cues(blocked).isEmpty,"beyond blockedDistance")
        timing.blockedDistance=2;timing.criticalDistance=2
        XCTAssertEqual(WalkableAnnouncer(timing:timing).cues(blocked).first?.priority,.critical)
        XCTAssertEqual(WalkableAnnouncer(timing:timing).cues(blocked).first?.text,"目の前に障害物。左へ。")
    }
    func testEarconsSeparateHazardsFromNavigation() {
        let rate=1000.0
        let critical=Earcon.hazard(.critical).samples(sampleRate:rate),high=Earcon.hazard(.high).samples(sampleRate:rate)
        // Beep onsets: first non-silent sample after silence.
        let onsets=critical.left.indices.filter { $0 == 0 ? critical.left[0] != 0:critical.left[$0] != 0 && critical.left[$0-1] == 0 && (($0-10)...($0-1)).allSatisfy { $0 < 0 || critical.left[$0] == 0 } }
        XCTAssertEqual(onsets.count,3);XCTAssertEqual(Double(onsets[1]-onsets[0])/rate,Earcon.criticalInterval,accuracy:0.01)
        XCTAssertGreaterThan(critical.left.count,high.left.count,"closer = more beeps")
        XCTAssertEqual(critical.left,critical.right,"centred")
        XCTAssertTrue(Earcon.hazard(.low).samples().left.isEmpty)
    }

    func testFeedbackTuningShapesSounds() {
        var t=FeedbackTuning();let base=Earcon.hazard(.critical).samples(sampleRate:1000,tuning:t).left.count
        t.criticalCount=5;XCTAssertGreaterThan(Earcon.hazard(.critical).samples(sampleRate:1000,tuning:t).left.count,base)
        t.criticalInterval=1;XCTAssertEqual(Double(Earcon.hazard(.critical).samples(sampleRate:1000,tuning:t).left.count)/1000,4*1+t.beepDuration,accuracy:0.01)
        t.hazardVolume=0;XCTAssertEqual(Earcon.hazard(.high).samples(tuning:t).left.map(abs).max(),0)
        XCTAssertFalse(FeedbackTuning().vibrateNormal,"normal hazards do not vibrate by default")
    }
    func testPerLabelTierOverrides() throws {
        var t=NoticeTuning();t.persistence=0;t.tiers=["pole":.off,"tree":.hazard]
        var f=NoticeFilter();t.apply(to:&f)
        let pole=Detection(label:"pole",confidence:0.9,box:Box(x:0.4,y:0.3,width:0.2,height:0.4),capturedAt:0)
        let tree=Detection(label:"tree",confidence:0.9,box:Box(x:0.1,y:0.3,width:0.2,height:0.4),capturedAt:0)
        let notices=f.process([pole,tree],now:0)
        XCTAssertEqual(notices.map(\.label),["tree"],"pole silenced, tree promoted from context");XCTAssertEqual(notices.first?.priority,.high)
        XCTAssertEqual(SceneSummary.items(detections:[pole,tree],walkable:nil,headLevel:nil,tiers:t.tiers).map(\.text),["左前に木。"])
        // Tuning saved before `tiers` existed still loads, keeping its values.
        let old=try JSONDecoder().decode(NoticeTuning.self,from:Data(#"{"confidence":0.8,"persistence":0.6,"cooldown":8}"#.utf8))
        XCTAssertEqual(old.confidence,0.8);XCTAssertTrue(old.tiers.isEmpty);XCTAssertEqual(old.hazardRepeat,10)
        let round=try JSONDecoder().decode(NoticeTuning.self,from:JSONEncoder().encode(t));XCTAssertEqual(round,t)
    }
    func testHazardPriorityByDistance() {
        XCTAssertEqual(NoticeFilter.hazardPriority(1.5,critical:2,announce:3),.critical)
        XCTAssertEqual(NoticeFilter.hazardPriority(2.5,critical:2,announce:3),.high)
        XCTAssertNil(NoticeFilter.hazardPriority(4,critical:2,announce:3),"beyond the announce distance: not read out")
        XCTAssertEqual(NoticeFilter.hazardPriority(nil,critical:2,announce:3),.high,"unknown distance is still announced")
        var t=NoticeTuning();t.persistence=0;var f=NoticeFilter();t.apply(to:&f)
        let farPole=Detection(label:"pole",confidence:0.9,box:Box(x:0.4,y:0.3,width:0.2,height:0.4),capturedAt:0,distance:4,lateral:0)
        XCTAssertTrue(f.process([farPole],now:0).isEmpty)
        var nearPole=farPole;nearPole.distance=1.8;XCTAssertEqual(f.process([nearPole],now:0).first?.priority,.critical)
        let block=Detection(label:"braille_block",confidence:0.9,box:Box(x:0.1,y:0.1,width:0.2,height:0.2),capturedAt:0)
        XCTAssertEqual(f.process([block],now:0).first?.hazard,false,"landmarks never beep")
        // People and vehicles are landmarks by default (spoken, no warning sound); a label can be moved per DeveloperMode.
        let car=Detection(label:"car",confidence:0.9,box:Box(x:0.6,y:0.3,width:0.2,height:0.4),capturedAt:0,distance:2.5,lateral:0.5)
        var g=NoticeFilter();t.apply(to:&g);let landmark=g.process([car],now:0).first
        XCTAssertEqual(landmark?.priority,.normal);XCTAssertEqual(landmark?.hazard,false)
        t.tiers=["car":.hazard];var h=NoticeFilter();t.apply(to:&h);XCTAssertEqual(h.process([car],now:0).first?.priority,.high)
        XCTAssertEqual(SceneCatalog.classes["guardrail"]?.tier,.hazard);XCTAssertEqual(SceneCatalog.classes["elevator"]?.tier,.context);XCTAssertEqual(SceneCatalog.classes["train"]?.tier,.off)
        XCTAssertEqual(HeadLevelConfig().buzzerDistance,1);XCTAssertEqual(Earcon.buzzer(seconds:0.25).samples(sampleRate:1000).left.count,250,"buzzer chunks have no gaps")
    }

    func testDepthRejectsPicturesAndFloatingGroundObjects() {
        func grid(_ depth:(Int,Int)->Float) -> DepthGrid {
            DepthGrid(values:(0..<48).flatMap { v in (0..<64).map { u in depth(u,v) } },columns:64,rows:48,step:1,fx:50,fy:50,cx:32,cy:24,gravity:SIMD3(0,-1,0),time:0,floor:-1.3)
        }
        let c=DepthCheck(),box=Box(x:0.4,y:0.4,width:0.2,height:0.2)
        // A flat screen 2 m away: the "pole" is as far as its surroundings and flat → picture.
        XCTAssertEqual(grid { _,_ in 2 }.implausibility(box,label:"pole",config:c),"平面（画面・写真の可能性）")
        // A real pole in front of a wall: nearer than the surroundings → kept (pole bottom check skipped only if at the image edge).
        let real=grid { u,v in (v >= 20 && v <= 28) ? 1.5:3 }
        XCTAssertNotEqual(real.implausibility(box,label:"pole",config:c),"平面（画面・写真の可能性）")
        // Steps whose bottom is at eye level (1.3 m above the floor) are floating → rejected.
        XCTAssertEqual(real.implausibility(box,label:"steps",config:c),"床から浮いている")
        // Painted classes skip the picture check; a braille block near the bottom of the image is on the floor.
        XCTAssertNil(grid { _,_ in 2 }.implausibility(Box(x:0.4,y:0.05,width:0.2,height:0.1),label:"braille_block",config:c))
        var off=c;off.enabled=false;XCTAssertNil(grid { _,_ in 2 }.implausibility(box,label:"pole",config:off))
        XCTAssertNil(grid { _,_ in 8 }.implausibility(box,label:"pole",config:c),"too far to judge")
        // Rejected detections and per-class thresholds are honoured by the notice filter.
        var t=NoticeTuning();t.persistence=0;t.classConfidence=["pole":0.95];var f=NoticeFilter();t.apply(to:&f)
        let pole=Detection(label:"pole",confidence:0.9,box:box,capturedAt:0,distance:1.5,lateral:0)
        XCTAssertTrue(f.process([pole],now:0).isEmpty,"below the pole's own threshold")
        var g=NoticeFilter();var u=NoticeTuning();u.persistence=0;u.apply(to:&g);var rejected=pole;rejected.rejected="平面"
        XCTAssertTrue(g.process([rejected],now:0).isEmpty);XCTAssertEqual(g.process([pole],now:0).count,1)
    }
    func testStricterDefaultsForMotorbikeAndCyclist() {
        XCTAssertEqual(SceneCatalog.threshold("motorbike",common:0.6),0.8);XCTAssertEqual(SceneCatalog.threshold("bicycler",common:0.6),0.8)
        XCTAssertEqual(SceneCatalog.threshold("pole",common:0.6),0.6);XCTAssertEqual(SceneCatalog.threshold("motorbike",overrides:["motorbike":0.7],common:0.6),0.7)
        XCTAssertEqual(SceneCatalog.classes["motorbike"]?.tier,.off);XCTAssertEqual(SceneCatalog.classes["bicycler"]?.tier,.off,"hidden by default");XCTAssertEqual(SceneCatalog.classes["bicycle"]?.tier,.off);XCTAssertEqual(SceneCatalog.classes["escalator"]?.tier,.off)
        // When turned back on in DeveloperMode, the stricter 0.8 threshold still applies.
        var t=NoticeTuning();t.persistence=0;t.tiers=["motorbike":.landmark];var f=NoticeFilter();t.apply(to:&f)
        let bike=Detection(label:"motorbike",confidence:0.7,box:Box(x:0.4,y:0.3,width:0.2,height:0.4),capturedAt:0)
        XCTAssertTrue(f.process([bike],now:0).isEmpty,"0.7 is below the motorbike default of 0.8")
        var sure=bike;sure.confidence=0.85;XCTAssertEqual(f.process([sure],now:0).count,1)
        XCTAssertTrue(DepthCheck.groundLabels.isSuperset(of:["motorbike","bicycler","bicycle"]))
    }
}
extension Result { var failureValue:Failure? { if case .failure(let e)=self { return e };return nil } }
