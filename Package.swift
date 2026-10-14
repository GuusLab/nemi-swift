// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NemiKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .visionOS(.v1),
        .watchOS(.v8),
    ],
    products: [
        .library(name: "NemiKit", targets: ["NemiKit"]),
        .library(name: "NemiKitUI", targets: ["NemiKitUI"]),
    ],
    targets: [
        .target(name: "NemiKit"),
        .target(name: "NemiKitUI", dependencies: ["NemiKit"]),
        .testTarget(name: "NemiKitTests", dependencies: ["NemiKit"]),
    ],
    swiftLanguageModes: [.v6]
)
