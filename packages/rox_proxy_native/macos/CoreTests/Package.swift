// swift-tools-version: 5.9
import PackageDescription

// Standalone test package for the proxy core (SwiftNIO + Certificate + Models).
// The app module (rox_proxy_native) cannot be linked outside Xcode/Flutter
// because it depends on FlutterMacOS, so the pure Swift sources are compiled
// here directly via symlinks in Tests/CoreTests.
//
// How to run:
//   cd packages/rox_proxy_native/macos/CoreTests && swift test
let package = Package(
    name: "RoxProxyCoreTests",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.27.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.2.0"),
    ],
    targets: [
        .testTarget(
            name: "CoreTests",
            dependencies: [
                .product(name: "NIOCore",   package: "swift-nio"),
                .product(name: "NIOPosix",  package: "swift-nio"),
                .product(name: "NIOHTTP1",  package: "swift-nio"),
                .product(name: "NIOTLS",    package: "swift-nio"),
                .product(name: "NIOEmbedded", package: "swift-nio"),
                .product(name: "NIOSSL",    package: "swift-nio-ssl"),
                .product(name: "X509",      package: "swift-certificates"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "Crypto",    package: "swift-crypto"),
            ]
        )
    ]
)
