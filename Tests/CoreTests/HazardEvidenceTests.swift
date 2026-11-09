import XCTest
@testable import GuideCore

final class HazardEvidenceTests:XCTestCase {
    func testUnknownOrInvalidObjectDistanceIsCheckingRatherThanCaution() throws {
        for distance:Double? in [nil,.nan,.infinity,0,-0.2] {
            let detection=Detection(label:"pole",confidence:0.95,box:Box(x:0.3,y:0.2,width:0.4,height:0.5),capturedAt:0,distance:distance)
            var filter=NoticeFilter();filter.persistence=0
            XCTAssertTrue(filter.process([detection],now:0).isEmpty)
            let item=try XCTUnwrap(SceneSummary.items(detections:[detection],walkable:nil,headLevel:nil).first)
            XCTAssertTrue(item.distanceUnavailable)
            XCTAssertEqual(item.brief,"距離確認中")
            XCTAssertLessThan(item.priority,.high)
        }
    }

    func testCloseDepthFlowsThroughHeadGroundAndObjectDangerJudgments() throws {
        for distance:Float in [0.1,0.15,0.2,0.25,0.49,0.5] {
            XCTAssertTrue(DepthGrid.validDepth(distance))
            let points=[SIMD3<Float>](repeating:SIMD3(0,0.2,-distance),count:20)
            let head=HeadLevelGeometry.evaluate(points:points,gravity:SIMD3(0,-1,0),cameraHeight:1.3)
            XCTAssertEqual(head.hit?.stage,.danger,"head distance=\(distance)")
            let samples=[WalkSample](repeating:WalkSample(forward:distance,lateral:0,up:-0.8),count:20)
            let ground=WalkableGeometry.profile(samples,floor:-1.3)
            XCTAssertEqual(WalkableAnnouncer().cues(ground).first?.priority,.critical)
            let grid=DepthGrid(values:[Float](repeating:distance,count:64*48),columns:64,rows:48,step:1,fx:50,fy:50,cx:32,cy:24,gravity:SIMD3(0,-1,0),time:0,floor:-1.3)
            let box=Box(x:0.3,y:0.2,width:0.4,height:0.5)
            let location=try XCTUnwrap(grid.locate(box))
            XCTAssertEqual(location.distance,Double(distance),accuracy:0.0001)
            XCTAssertNil(grid.implausibility(box,label:"pole",config:DepthCheck()),"close wall/cropped pole must not be rejected as flat or floating")
            let detection=Detection(label:"pole",confidence:0.95,box:box,capturedAt:0,distance:location.distance)
            XCTAssertEqual(SceneSummary.items(detections:[detection],walkable:nil,headLevel:nil).first?.priority,.critical)
        }
        for invalid:Float in [0,-1,.nan,.infinity,0.05,5] { XCTAssertFalse(DepthGrid.validDepth(invalid)) }
    }

    func testObjectInteriorFindsCloseSurfaceInsteadOfBackgroundAtBottomEdge() throws {
        var values=[Float](repeating:2,count:64*48)
        // Upright portrait box centre maps to landscape (column 32, row 24).
        for v in 19...29 { for u in 25...39 { values[v*64+u]=0.25 } }
        let grid=DepthGrid(values:values,columns:64,rows:48,step:1,fx:50,fy:50,cx:32,cy:24,gravity:SIMD3(0,-1,0),time:0)
        let location=try XCTUnwrap(grid.locate(Box(x:0.3,y:0.2,width:0.4,height:0.6)))
        XCTAssertEqual(location.distance,0.25,accuracy:0.001)
    }

    func testDistantSideDropDoesNotCauseCautionButNearDropDoes() {
        for distance:Float in [0.7,2.5] {
            let samples=[WalkSample](repeating:WalkSample(forward:distance,lateral:0.34,up:-1.5),count:20)
            let profile=WalkableGeometry.profile(samples,floor:-1.3)
            XCTAssertNotNil(profile.right)
            let cues=WalkableAnnouncer().cues(profile)
            XCTAssertEqual(cues.contains { $0.priority >= .high },distance == 0.7)
        }
    }

    func testCloserGroundDangerIsNotHiddenByHeadCaution() {
        let ground=WalkableProfile(blockedAhead:0.25,dropAhead:nil,left:nil,right:nil,passSide:nil,groundSeen:false)
        let head=HeadLevelHit(distance:0.7,lateral:0,height:1.5,count:20,stage:.caution)
        let items=SceneSummary.items(detections:[],walkable:ground,headLevel:head)
        XCTAssertEqual(items.first?.priority,.critical)
        XCTAssertEqual(items.first?.brief,"止まって")
    }

    func testInvalidDistanceDoesNotHideMeasuredHazardOfSameClass() {
        let box=Box(x:0.3,y:0.2,width:0.4,height:0.5)
        let close=Detection(label:"pole",confidence:0.95,box:box,capturedAt:0,distance:0.25)
        let unknown=Detection(label:"pole",confidence:0.95,box:box,capturedAt:0,distance:.nan)
        for detections in [[close,unknown],[unknown,close]] {
            let item=SceneSummary.items(detections:detections,walkable:nil,headLevel:nil).first
            XCTAssertEqual(item?.priority,.critical)
            XCTAssertEqual(item?.distanceUnavailable,false)
        }
    }

    func testCloseRangeDefaultsMigrateAndCustomValuesRemain() throws {
        for (key,field,old,expected) in [("dev.headLevelConfig","minDistance",0.3,0.1),("dev.walkableConfig","nearest",0.5,0.1)] {
            let saved=try JSONSerialization.data(withJSONObject:[field:old,"customField":7])
            let migrated=try XCTUnwrap(WarningDistanceDefaults.migrated(saved,forKey:key))
            let actual=try XCTUnwrap(try JSONSerialization.jsonObject(with:migrated) as? [String:Double])
            XCTAssertEqual(try XCTUnwrap(actual[field]),expected,accuracy:0.0001)
            XCTAssertEqual(actual["customField"],7)
            XCTAssertNil(WarningDistanceDefaults.migrated(migrated,forKey:key))
            let custom=try JSONSerialization.data(withJSONObject:[field:0.18])
            XCTAssertNil(WarningDistanceDefaults.migrated(custom,forKey:key))
        }
    }
}
