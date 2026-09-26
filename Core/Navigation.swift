import Foundation

public enum Maneuver: String, Sendable, CaseIterable {
    case straight, slightLeft, left, sharpLeft, slightRight, right, sharpRight, uturn, arrive
    // Geometry-only turn at the end of the current step. Speech still requires a reliable course (TurnGuidance).
    public static func between(_ current:RouteStep,_ next:RouteStep?)->Maneuver {
        guard let next,current.shape.count>=2,next.shape.count>=2 else { return .arrive }
        let inLength=Geometry.length(current.shape),outLength=Geometry.length(next.shape)
        let before=Geometry.point(along:current.shape,at:max(0,inLength-10)).coordinate
        let after=Geometry.point(along:next.shape,at:min(outLength,10)).coordinate
        guard let end=current.shape.last,let start=next.shape.first,before.distance(to:end)>0.3,start.distance(to:after)>0.3 else { return .straight }
        let angle=(Geometry.bearing(start,after)-Geometry.bearing(before,end)+540).truncatingRemainder(dividingBy:360)-180
        switch abs(angle) {
        case ..<20: return .straight
        case ..<45: return angle>0 ? .slightRight:.slightLeft
        case ..<135: return angle>0 ? .right:.left
        case ..<165: return angle>0 ? .sharpRight:.sharpLeft
        default: return .uturn
        }
    }
    public var text:String { switch self {
        case .straight:return "直進";case .slightLeft:return "やや左";case .left:return "左方向";case .sharpLeft:return "大きく左"
        case .slightRight:return "やや右";case .right:return "右方向";case .sharpRight:return "大きく右";case .uturn:return "折り返し";case .arrive:return "終点"
    } }
    public var symbol:String { switch self {
        case .straight:return "arrow.up";case .slightLeft:return "arrow.up.left";case .left:return "arrow.turn.up.left";case .sharpLeft:return "arrow.down.left"
        case .slightRight:return "arrow.up.right";case .right:return "arrow.turn.up.right";case .sharpRight:return "arrow.down.right";case .uturn:return "arrow.uturn.down";case .arrive:return "flag.checkered"
    } }
}
public struct RouteProgress: Sendable {
    public var stepIndex:Int;public var distanceToStepEnd:Double;public var remainingDistance:Double
    public var lookahead:Coordinate;public var maneuver:Maneuver;public var offRouteDistance:Double
}
public enum RouteTracker {
    public static func progress(route:WalkRoute,stepIndex:Int,position:Coordinate,lookahead:Double=15)->RouteProgress? {
        guard !route.steps.isEmpty else { return nil }
        let i=min(max(0,stepIndex),route.steps.count-1),step=route.steps[i]
        let length=Geometry.length(step.shape),projection=Geometry.project(position,onto:step.shape)
        let along=projection.fraction*length,toEnd=max(0,length-along)
        let later=route.steps.dropFirst(i+1).reduce(0) { $0+Geometry.length($1.shape) }
        let next=i+1<route.steps.count ? route.steps[i+1]:nil
        let target:Coordinate
        if toEnd>=lookahead || next == nil { target=Geometry.point(along:step.shape,at:min(length,along+lookahead)).coordinate }
        else { target=Geometry.point(along:next!.shape,at:lookahead-toEnd).coordinate }
        return RouteProgress(stepIndex:i,distanceToStepEnd:toEnd,remainingDistance:toEnd+later,lookahead:target,maneuver:Maneuver.between(step,next),offRouteDistance:projection.distance)
    }
    /// Signed angle (-180...180, positive = right) from the device heading to the target.
    public static func relativeBearing(from position:Coordinate,to target:Coordinate,heading:Double)->Double {
        (Geometry.bearing(position,target)-heading+540).truncatingRemainder(dividingBy:360)-180
    }
    public static func shape(of route:WalkRoute)->[Coordinate] {
        route.steps.reduce(into:[Coordinate]()) { result,step in result += result.last == step.shape.first ? Array(step.shape.dropFirst()):step.shape }
    }
}
