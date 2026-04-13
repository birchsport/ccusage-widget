// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CCUsageWidget",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CCUsageWidget",
            path: "CCUsageWidget",
            exclude: ["Info.plist"],
            resources: []
        )
    ]
)
