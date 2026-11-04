// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AWSStatus",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "AWSStatus", targets: ["AWSStatus"])],
    targets: [
        .target(name: "StatusCore"),
        .executableTarget(name: "AWSStatus", dependencies: ["StatusCore"]),
        .testTarget(name: "StatusCoreTests", dependencies: ["StatusCore"])
    ]
)
