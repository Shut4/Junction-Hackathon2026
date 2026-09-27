import Foundation

@main struct NetworkBenchmark {
    static func milliseconds(_ operation: () throws -> Void) rethrows -> Double {
        let started=ProcessInfo.processInfo.systemUptime
        try operation()
        return (ProcessInfo.processInfo.systemUptime-started)*1000
    }
    static func percentile(_ values:[Double],_ fraction:Double)->Double {
        let sorted=values.sorted()
        return sorted[min(sorted.count-1,Int(Double(sorted.count-1)*fraction))]
    }
    static func main() throws {
        guard CommandLine.arguments.count==2 else { throw NSError(domain:"usage: benchmark_network <network.json>",code:2) }
        let data=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
        var network:Network!
        let decode=try milliseconds { network=try JSONDecoder().decode(Network.self,from:data) }
        let samples=stride(from:0,to:network.nodes.count,by:max(1,network.nodes.count/40)).prefix(40).map { network.nodes[$0].coordinate }
        let matcher=RoadMatcher(network:network)
        var matchTimes:[Double]=[]
        for point in samples { matchTimes.append(milliseconds { _=matcher.candidates(at:point,radius:35) }) }
        let start=network.destinations.first!.nodeID,end=network.destinations.last!.nodeID
        var routeTimes:[Double]=[]
        for _ in 0..<20 { routeTimes.append(milliseconds { _=Router(network:network).route(from:start,to:end,blocked:[]) }) }
        let extents=[Coordinate(network.bounds.south+0.0001,(network.bounds.west+network.bounds.east)/2),Coordinate(network.bounds.north-0.0001,(network.bounds.west+network.bounds.east)/2),Coordinate((network.bounds.south+network.bounds.north)/2,network.bounds.west+0.0001),Coordinate((network.bounds.south+network.bounds.north)/2,network.bounds.east-0.0001)]
        var offRoadTimes:[Double]=[]
        for point in extents { offRoadTimes.append(milliseconds { _=Router(network:network).resolveOffRoadRoute(from:point,to:end,blocked:[]) }) }
        print(String(format:"bytes=%d decode_ms=%.2f",data.count,decode))
        print(String(format:"road_match_ms p50=%.2f p95=%.2f max=%.2f",percentile(matchTimes,0.5),percentile(matchTimes,0.95),matchTimes.max()!))
        print(String(format:"route_ms p50=%.2f p95=%.2f max=%.2f",percentile(routeTimes,0.5),percentile(routeTimes,0.95),routeTimes.max()!))
        print(String(format:"offroad_route_ms p50=%.2f max=%.2f",percentile(offRoadTimes,0.5),offRoadTimes.max()!))
    }
}
