import XCTest
@testable import GuideCore

final class CaneProtocolTests:XCTestCase {
    func testSharedDangerVectorAndSequenceRollover() {
        let command=CaneCommand(state:.danger,distance:1500)
        XCTAssertEqual(Array(command.data(sequence:1)),[1,2,1,0,0xE8,3,0xDC,5,0,0])
        var sequence=UInt16.max
        XCTAssertEqual(Array(command.data(sequence:sequence))[2...3],[255,255])
        sequence &+= 1
        XCTAssertEqual(Array(command.data(sequence:sequence))[2...3],[0,0])
        XCTAssertEqual(Array(CaneCommand(state:.clear,distance:100,manual:true).data(sequence:0)),[1,0,0,0,0xE8,3,255,255,2,0])
        XCTAssertEqual(Array(CaneCommand(state:.unavailable,distance:100).data(sequence:0))[6...7],[255,255])
    }
    func testStatusDecodingAndMalformedPackets() {
        let data=Data([1,2,3,1,0x34,0x12,0x78,0x56,0x34,0x12])
        let status=CaneStatus(data:data)
        XCTAssertEqual(status?.state,.danger);XCTAssertEqual(status?.sequence,0x1234)
        XCTAssertEqual(status?.uptime,0x12345678);XCTAssertEqual(status?.errors,3);XCTAssertEqual(status?.gpioHigh,true)
        XCTAssertNil(CaneStatus(data:data.dropLast()))
        for (offset,value):(Int,UInt8) in [(0,2),(1,4),(2,4),(3,2)] {
            var malformed=data;malformed[offset]=value;XCTAssertNil(CaneStatus(data:malformed))
        }
    }
    func testContinuityFreshnessAndDisabledDetection() {
        var state=CaneDetectionState()
        state.update(state:.danger,distance:1.5,floorMeasured:true,capturedAt:1,now:1)
        XCTAssertEqual(state.current(now:1,enabled:true).state,.unavailable)
        // Repeated sends are not new depth frames.
        XCTAssertEqual(state.current(now:1.1,enabled:true).state,.unavailable)
        state.update(state:.danger,distance:1.4,floorMeasured:true,capturedAt:1.2,now:1.2)
        XCTAssertEqual(state.current(now:1.2,enabled:true),CaneCommand(state:.danger,distance:1400,floorMeasured:true))
        XCTAssertEqual(state.current(now:1.81,enabled:true).state,.unavailable)
        state.update(state:.clear,distance:nil,floorMeasured:false,capturedAt:2,now:2)
        XCTAssertEqual(state.current(now:2,enabled:true).state,.unavailable)
        state.update(state:.clear,distance:nil,floorMeasured:false,capturedAt:2.2,now:2.2)
        XCTAssertEqual(state.current(now:2.2,enabled:true).state,.clear)
        XCTAssertEqual(state.current(now:2.2,enabled:false).state,.unavailable)
        state.update(state:.danger,distance:1,floorMeasured:false,capturedAt:2.4,now:2.4)
        XCTAssertEqual(state.current(now:2.4,enabled:true).state,.unavailable)
        state.update(state:.unavailable,distance:nil,floorMeasured:false,capturedAt:2.5,now:2.5)
        XCTAssertEqual(state.current(now:2.5,enabled:true).state,.unavailable)
    }
    func testInvalidOldAndDiscontinuousFramesDoNotConfirm() {
        var state=CaneDetectionState()
        for time in [1.0,2.0] {
            state.update(state:.danger,distance:1,floorMeasured:false,capturedAt:time,now:time)
            XCTAssertEqual(state.current(now:time,enabled:true).state,.unavailable)
        }
        state.update(state:.danger,distance:1,floorMeasured:false,capturedAt:2,now:3)
        XCTAssertEqual(state.current(now:3,enabled:true).state,.unavailable)
        state.update(state:.clear,distance:nil,floorMeasured:false,capturedAt:.nan,now:3)
        XCTAssertEqual(state.current(now:3,enabled:true).state,.unavailable)
    }
}
