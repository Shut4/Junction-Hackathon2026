import XCTest
@testable import GuideCore

final class WarningDistanceTests:XCTestCase {
    func testHeadLevelDistanceBoundaries() {
        for (distance,expected):(Float,HeadLevelStage?) in [(0.5,.danger),(0.6,.danger),(0.61,.caution),(1,.caution),(1.01,nil),(2,nil)] {
            let points=[SIMD3<Float>](repeating:SIMD3(0,0.3,-distance),count:20)
            let result=HeadLevelGeometry.evaluate(points:points,gravity:SIMD3(0,-1,0),cameraHeight:1.3)
            XCTAssertEqual(result.hit?.stage,expected,"distance=\(distance)")
        }
        XCTAssertEqual(HeadLevelConfig().buzzerDistance,0.5)
    }
    func testObjectAudioAndSceneUseSameReducedDistances() {
        let tuning=NoticeTuning()
        for (distance,expected):(Double,SpeechPriority?) in [(0.5,.critical),(0.6,.critical),(0.61,.high),(1,.high),(1.01,nil),(2,nil)] {
            var tuning=tuning;tuning.persistence=0
            var filter=NoticeFilter();tuning.apply(to:&filter)
            let detection=Detection(label:"pole",confidence:0.9,box:Box(x:0.4,y:0.3,width:0.2,height:0.4),capturedAt:0,distance:distance,lateral:0)
            XCTAssertEqual(filter.process([detection],now:0).first?.priority,expected,"audio distance=\(distance)")
            XCTAssertEqual(SceneSummary.items(detections:[detection],walkable:nil,headLevel:nil).first?.priority,expected,"scene distance=\(distance)")
        }
        XCTAssertEqual(NoticeFilter.hazardPriority(nil,critical:tuning.criticalDistance,announce:tuning.announceDistance),.high)
    }
    func testGroundObstaclesAndDropsAreQuietBeyondOneMetre() {
        for (distance,expected):(Float,SpeechPriority?) in [(0.5,.critical),(0.6,.critical),(0.61,.high),(1,.high),(1.01,nil),(2,nil)] {
            for height:Float in [-0.8,-1.5] {
                let samples=(0..<20).map { _ in WalkSample(forward:distance,lateral:0,up:height) }
                let profile=WalkableGeometry.profile(samples,floor:-1.3)
                let key=height == -0.8 ? "blocked":"drop"
                XCTAssertEqual(WalkableAnnouncer().cues(profile).first(where:{$0.key == key})?.priority,expected,"\(key) distance=\(distance)")
            }
        }
    }
    func testMigrationUpdatesOldDefaultsButKeepsCustomValuesAndOtherFields() throws {
        let fixtures:[(String,[String:Double],[String:Double])]=[
            ("dev.headLevelConfig",["maxDistance":2.5,"dangerDistance":2,"buzzerDistance":1,"minPoints":30],
             ["maxDistance":1,"dangerDistance":0.6,"buzzerDistance":0.5,"minPoints":30]),
            ("dev.noticeTuning",["announceDistance":3,"criticalDistance":2,"confidence":0.8],
             ["announceDistance":1,"criticalDistance":0.6,"confidence":0.8]),
            ("dev.walkableTiming",["blockedDistance":3,"criticalDistance":1.8,"dropDistance":3,"repeatHigh":12],
             ["blockedDistance":1,"criticalDistance":0.6,"dropDistance":1,"repeatHigh":12])]
        for (key,old,expected) in fixtures {
            let data=try JSONSerialization.data(withJSONObject:old)
            let result=try XCTUnwrap(WarningDistanceDefaults.migrated(data,forKey:key))
            let actual=try XCTUnwrap(try JSONSerialization.jsonObject(with:result) as? [String:Double])
            XCTAssertEqual(Set(actual.keys),Set(expected.keys))
            for (field,value) in expected { XCTAssertEqual(try XCTUnwrap(actual[field]),value,accuracy:0.00001) }
            XCTAssertNil(WarningDistanceDefaults.migrated(result,forKey:key),"migration must be idempotent")
        }
        // Devices which already migrated to the previous 1m stop default also update.
        for (key,field) in [("dev.headLevelConfig","dangerDistance"),("dev.noticeTuning","criticalDistance"),("dev.walkableTiming","criticalDistance")] {
            let saved=try JSONSerialization.data(withJSONObject:[field:1.0])
            let migrated=try XCTUnwrap(WarningDistanceDefaults.migrated(saved,forKey:key))
            XCTAssertEqual(try XCTUnwrap((try JSONSerialization.jsonObject(with:migrated) as? [String:Double])?[field]),0.6,accuracy:0.00001)
        }
        for (key,fields) in [("dev.headLevelConfig",["maxDistance"]),("dev.noticeTuning",["announceDistance"]),("dev.walkableTiming",["blockedDistance","dropDistance"])] {
            let saved=try JSONSerialization.data(withJSONObject:Dictionary(uniqueKeysWithValues:fields.map { ($0,2.0) }))
            let migrated=try XCTUnwrap(WarningDistanceDefaults.migrated(saved,forKey:key))
            let actual=try XCTUnwrap(try JSONSerialization.jsonObject(with:migrated) as? [String:Double])
            for field in fields { XCTAssertEqual(actual[field],1) }
            XCTAssertNil(WarningDistanceDefaults.migrated(migrated,forKey:key))
        }
        let custom=try JSONSerialization.data(withJSONObject:["maxDistance":1.7,"dangerDistance":0.8,"buzzerDistance":0.0])
        XCTAssertNil(WarningDistanceDefaults.migrated(custom,forKey:"dev.headLevelConfig"))
        let partial=try JSONSerialization.data(withJSONObject:["dangerDistance":2,"maxDistance":1.7,"customField":"keep"] as [String:Any])
        let result=try XCTUnwrap(WarningDistanceDefaults.migrated(partial,forKey:"dev.headLevelConfig"))
        let values=try XCTUnwrap(try JSONSerialization.jsonObject(with:result) as? [String:Any])
        XCTAssertEqual(try XCTUnwrap(values["dangerDistance"] as? Double),0.6,accuracy:0.00001)
        XCTAssertEqual(values["maxDistance"] as? Double,1.7)
        XCTAssertEqual(values["customField"] as? String,"keep")
        XCTAssertNil(values["buzzerDistance"],"missing fields are filled by the app's normal default loader")
        XCTAssertNil(WarningDistanceDefaults.migrated(Data("invalid".utf8),forKey:"dev.headLevelConfig"))
        XCTAssertNil(WarningDistanceDefaults.migrated(Data("{}".utf8),forKey:"unknown"))
    }
}
