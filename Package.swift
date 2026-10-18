// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TransferHub",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TransferHub", targets: ["TransferHub"])
    ],
    targets: [
        .executableTarget(name: "TransferHub"),
        .testTarget(name: "TransferHubTests", dependencies: ["TransferHub"])
    ]
)
