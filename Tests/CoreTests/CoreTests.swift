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
        XCTAssertEqual(a.update(angle:90,reason:"",now:1.3),"右へ約90度、向きを変えてください。")
        XCTAssertNil(a.update(angle:92,reason:"",now:5))
        XCTAssertEqual(a.update(angle:92,reason:"",now:11.4),"右へ約90度、向きを変えてください。")
        XCTAssertNil(a.update(angle:0,reason:"",now:12));XCTAssertNil(a.update(angle:0,reason:"",now:13))
        XCTAssertEqual(a.update(angle:0,reason:"",now:15.5),"正面方向です。そのまま進んでください。")
        XCTAssertNil(a.update(angle:0,reason:"",now:40))
        XCTAssertNil(a.update(angle:nil,reason:"保留",now:41));XCTAssertEqual(a.update(angle:nil,reason:"保留",now:44),"保留");XCTAssertNil(a.update(angle:nil,reason:"保留",now:60))
        a.reset();XCTAssertNil(a.update(angle:0,reason:"",now:61));XCTAssertEqual(a.update(angle:0,reason:"",now:62.5),"正面方向です。そのまま進んでください。")
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
}
extension Result { var failureValue:Failure? { if case .failure(let e)=self { return e };return nil } }
