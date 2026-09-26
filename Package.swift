// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "GuideCore", platforms: [.macOS(.v14)], products: [.library(name: "GuideCore", targets: ["GuideCore"])], targets: [.target(name: "GuideCore", path: "Core"), .testTarget(name: "CoreTests", dependencies: ["GuideCore"], path: "Tests/CoreTests")])
