import Foundation

/// Where the app keeps its files. UI tests get an isolated directory so they never read or overwrite real reports.
enum AppFiles {
    static let directory:URL = {
        #if DEBUG
        let arguments=ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing") {
            let url=URL.temporaryDirectory.appending(path:"JunctionGuide-UITest")
            if arguments.contains("--reset-test-data") { try? FileManager.default.removeItem(at:url) }
            return url
        }
        #endif
        return URL.applicationSupportDirectory.appending(path:"JunctionGuide")
    }()
    static func reportURL(networkID:String,simulated:Bool)->URL {
        if networkID == "kokura-ground-osm" { return directory.appending(path:simulated ? "simulation-reports.json":"real-reports.json") }
        let safe=networkID.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0:"-" }
        return directory.appending(path:"\(simulated ? "simulation":"real")-reports-\(String(safe)).json")
    }
}
