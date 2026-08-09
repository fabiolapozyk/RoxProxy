// swift-tools-version: 5.9
import PackageDescription

// Standalone test package for the Map Local Swift modules.
// The app module (rox_proxy_native) cannot be linked outside Xcode/Flutter
// because it depends on FlutterMacOS, so the Map Local sources are compiled
// here directly via symlinks in Tests/MapLocalTests.
let package = Package(
    name: "MapLocalTests",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    ],
    targets: [
        .testTarget(
            name: "MapLocalTests",
            dependencies: [
                .product(name: "NIOCore",  package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ]
        )
    ]
)
