// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WorkThreadTimeline",
    platforms: [.macOS("15.0")],
    products: [.executable(name: "WorkThreadTimeline", targets: ["WorkThreadTimeline"])],
    targets: [.executableTarget(name: "WorkThreadTimeline")]
)
