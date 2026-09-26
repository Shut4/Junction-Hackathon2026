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
}
