import XCTest
@testable import GuideCore

final class GuidanceStatusTests:XCTestCase {
    func testNavigationAndOptionalSurroundingsKeepTheirSpeechLabels() {
        let policy=GuidanceSpeechPolicy()
        XCTAssertEqual(policy.message("左へ。",kind:.navigation,priority:.normal,now:0),"ナビ、左へ。")
        XCTAssertEqual(policy.message("点字ブロック。",kind:.surroundings,priority:.normal,now:2),"周囲、点字ブロック。")
    }
    func testAllHazardPrioritiesAreSilentBeforeEitherSpeechBackend() {
        let policy=GuidanceSpeechPolicy()
        for priority in SpeechPriority.allCases {
            XCTAssertNil(policy.message("障害物。",kind:.hazard,priority:priority,now:0))
        }
        XCTAssertNil(policy.message("",kind:.navigation,priority:.normal,now:0))
    }
    func testRepeatedCriticalHazardsNeverSuppressNavigation() {
        let policy=GuidanceSpeechPolicy()
        for now in [0.0,0.1,1,2,4,5,8,12] {
            XCTAssertNil(policy.message("止まって。",kind:.hazard,priority:.critical,now:now))
            XCTAssertNil(policy.message("ポール。",kind:.hazard,priority:.high,now:now))
            XCTAssertEqual(policy.message("左へ。",kind:.navigation,priority:.normal,now:now),"ナビ、左へ。")
        }
    }
    func testNavigationPrecedesQueuedLandmarkDescriptions() throws {
        let policy=GuidanceSpeechPolicy(),now=Date()
        var queue=SpeechQueue()
        let landmark=try XCTUnwrap(policy.message("横断歩道。",kind:.surroundings,priority:.normal,now:0))
        let navigation=try XCTUnwrap(policy.message("右へ。",kind:.navigation,priority:.normal,now:0))
        queue.enqueue(landmark,priority:policy.priority(for:.surroundings,requested:.normal),now:now)
        queue.enqueue(navigation,priority:policy.priority(for:.navigation,requested:.normal),route:true,now:now)
        XCTAssertEqual(queue.next(now:now)?.text,"ナビ、右へ。")
        XCTAssertEqual(queue.next(now:now)?.text,"周囲、横断歩道。")
    }
    func testUnreliableDirectionAnnouncesCheckingThenRecovers() {
        var announcer=DirectionAnnouncer()
        let policy=GuidanceSpeechPolicy()
        XCTAssertNil(announcer.update(angle:nil,reason:"方向を確認中です。",now:0))
        let checking=announcer.update(angle:nil,reason:"方向を確認中です。",now:3)
        XCTAssertEqual(policy.message(checking ?? "",kind:.navigation,priority:.normal,now:3),"ナビ、方向を確認中です。")
        XCTAssertNil(announcer.update(angle:nil,reason:"方向を確認中です。",now:6))
        XCTAssertNil(announcer.update(angle:90,reason:"",now:7))
        XCTAssertEqual(announcer.update(angle:90,reason:"",now:9),"右へ。")
    }
    func testBackgroundRouteFailuresDoNotInterruptAndRepeatedFailureSpeaksOnce() {
        var policy=RouteFailureFeedbackPolicy()
        let first=policy.feedback(for:RouteFailure.noRoute.message,origin:.background)
        XCTAssertFalse(first.showAlert);XCTAssertTrue(first.announce)
        for _ in 0..<10 {
            let repeated=policy.feedback(for:RouteFailure.noRoute.message,origin:.background)
            XCTAssertFalse(repeated.showAlert);XCTAssertFalse(repeated.announce)
        }
        let changed=policy.feedback(for:RouteFailure.blockedStart.message,origin:.background)
        XCTAssertFalse(changed.showAlert);XCTAssertTrue(changed.announce)
        policy.reset()
        XCTAssertTrue(policy.feedback(for:RouteFailure.noRoute.message,origin:.background).announce)
    }
    func testExplicitRouteSearchStillExplainsFailure() {
        var policy=RouteFailureFeedbackPolicy()
        _=policy.feedback(for:RouteFailure.noRoute.message,origin:.background)
        let explicit=policy.feedback(for:RouteFailure.noRoute.message,origin:.userInitiated)
        XCTAssertTrue(explicit.showAlert);XCTAssertFalse(explicit.announce)
        let empty=policy.feedback(for:"",origin:.background)
        XCTAssertFalse(empty.showAlert);XCTAssertFalse(empty.announce)
    }
    func testCompactDirectionMatchesSpeechDirection() {
        XCTAssertEqual(DirectionBucket.of(-90).shortText,"左へ")
        XCTAssertEqual(DirectionBucket.of(0).shortText,"直進")
        XCTAssertEqual(DirectionBucket.of(90).shortText,"右へ")
    }
    func testHazardSummaryKeepsFullDescriptionForAccessibility() throws {
        let detection=Detection(label:"pole",confidence:0.95,box:Box(x:0.4,y:0.2,width:0.2,height:0.5),capturedAt:0,distance:0.8)
        let item=try XCTUnwrap(SceneSummary.items(detections:[detection],walkable:nil,headLevel:nil).first)
        XCTAssertEqual(item.priority,.high)
        XCTAssertEqual(item.brief,"ポールに注意")
        XCTAssertNotEqual(item.text,item.brief)
        let hit=HeadLevelHit(distance:0.5,lateral:0,height:1.5,count:10,stage:.danger)
        let critical=try XCTUnwrap(SceneSummary.items(detections:[],walkable:nil,headLevel:hit).first)
        XCTAssertEqual(critical.brief,"止まって")
        XCTAssertEqual(critical.priority,.critical)
    }
    func testDropSummaryDoesNotLoseStepMeaning() throws {
        let profile=WalkableProfile(blockedAhead:nil,dropAhead:0.8,left:nil,right:nil,passSide:nil,groundSeen:true)
        let item=try XCTUnwrap(SceneSummary.items(detections:[],walkable:profile,headLevel:nil).first)
        XCTAssertEqual(item.brief,"段差注意")
        XCTAssertEqual(item.priority,.high)
    }
}
