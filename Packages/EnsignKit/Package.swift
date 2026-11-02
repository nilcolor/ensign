// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EnsignKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EnsignKit", targets: ["EnsignKit"]),
    ],
    targets: [
        .target(name: "EnsignKit"),
        .testTarget(name: "EnsignKitTests", dependencies: ["EnsignKit"]),
    ]
)
