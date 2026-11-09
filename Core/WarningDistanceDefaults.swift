import Foundation

/// Replaces legacy defaults in saved tuning without overwriting custom values or unrelated settings.
public enum WarningDistanceDefaults {
    public static func migrated(_ data:Data,forKey key:String)->Data? {
        let rules:[String:(old:[Double],new:Double)]
        switch key {
        case "dev.headLevelConfig":
            let d=HeadLevelConfig()
            rules=["minDistance":([0.3],Double(d.minDistance)),"maxDistance":([2.5,2,1],Double(d.maxDistance)),"dangerDistance":([2,1,0.6],Double(d.dangerDistance)),"buzzerDistance":([1,0.5],Double(d.buzzerDistance))]
        case "dev.walkableConfig":
            rules=["nearest":([0.5],Double(WalkableConfig().nearest))]
        case "dev.noticeTuning":
            let d=NoticeTuning()
            rules=["criticalDistance":([2,1,0.6],d.criticalDistance),"announceDistance":([3,2,1],d.announceDistance)]
        case "dev.walkableTiming":
            let d=WalkableTiming()
            rules=["blockedDistance":([3,2,1],Double(d.blockedDistance)),"criticalDistance":([1.8,1,0.6],Double(d.criticalDistance)),"dropDistance":([3,2,1],Double(d.dropDistance))]
        default: return nil
        }
        guard var saved=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else { return nil }
        var changed=false
        for (field,rule) in rules {
            if let value=saved[field] as? NSNumber,CFGetTypeID(value) != CFBooleanGetTypeID(),rule.old.contains(where: { abs(value.doubleValue-$0) < 0.000001 }) {
                saved[field]=rule.new;changed=true
            }
        }
        return changed ? try? JSONSerialization.data(withJSONObject:saved):nil
    }
}
