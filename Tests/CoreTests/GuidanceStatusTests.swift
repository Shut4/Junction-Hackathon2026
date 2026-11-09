import XCTest
@testable import GuideCore

final class GuidanceStatusTests:XCTestCase {
    func testSpeechCategoriesAreAudiblyDistinct() {
        var policy=GuidanceSpeechPolicy()
        XCTAssertEqual(policy.message("左へ。",kind:.navigation,priority:.normal,now:0),"ナビ、左へ。")
        XCTAssertEqual(policy.message("止まって。",kind:.hazard,priority:.critical,now:1),"危険、止まって。")
        XCTAssertEqual(policy.message("点字ブロック。",kind:.surroundings,priority:.normal,now:2),"周囲、点字ブロック。")
    }
    func testUrgentHazardSuppressesNavigationForFiveSeconds() {
        var policy=GuidanceSpeechPolicy()
        XCTAssertNotNil(policy.message("止まって。",kind:.hazard,priority:.critical,now:10))
        XCTAssertNil(policy.message("直進です。",kind:.navigation,priority:.normal,now:10.1))
        XCTAssertNil(policy.message("左へ。",kind:.navigation,priority:.normal,now:14.9))
        XCTAssertNotNil(policy.message("右へ。",kind:.navigation,priority:.normal,now:15))
    }
    func testRepeatedHazardsExtendSuppressionButLandmarksDoNot() {
        var policy=GuidanceSpeechPolicy()
        _=policy.message("障害物。",kind:.hazard,priority:.high,now:0)
        _=policy.message("障害物。",kind:.hazard,priority:.high,now:4)
        XCTAssertNil(policy.message("直進。",kind:.navigation,priority:.normal,now:8))
        _=policy.message("横断歩道。",kind:.surroundings,priority:.normal,now:9)
        XCTAssertNotNil(policy.message("直進。",kind:.navigation,priority:.normal,now:9))
        XCTAssertNil(policy.message("",kind:.hazard,priority:.critical,now:10))
        XCTAssertNotNil(policy.message("直進。",kind:.navigation,priority:.normal,now:10))
    }
    func testCompactDirectionMatchesSpeechDirection() {
        XCTAssertEqual(DirectionBucket.of(-90).shortText,"左へ")
        XCTAssertEqual(DirectionBucket.of(0).shortText,"直進")
        XCTAssertEqual(DirectionBucket.of(90).shortText,"右へ")
    }
    func testHazardSummaryKeepsFullDescriptionForSpeech() throws {
        let detection=Detection(label:"pole",confidence:0.95,box:Box(x:0.4,y:0.2,width:0.2,height:0.5),capturedAt:0,distance:1.5)
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
        let profile=WalkableProfile(blockedAhead:nil,dropAhead:1.5,left:nil,right:nil,passSide:nil,groundSeen:true)
        let item=try XCTUnwrap(SceneSummary.items(detections:[],walkable:profile,headLevel:nil).first)
        XCTAssertEqual(item.brief,"段差注意")
        XCTAssertEqual(item.priority,.high)
    }
}
