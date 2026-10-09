// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GlideKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GlideCore", targets: ["GlideCore"]),
        .library(name: "GlideNet", targets: ["GlideNet"]),
    ],
    targets: [
        // Pure Swift/Foundation logic: protocol, gestures, pointer curve, momentum.
        // No Apple-only imports, so it builds and tests anywhere.
        .target(name: "GlideCore"),
        // Network.framework transport (Bonjour + TLS-PSK). Apple platforms only.
        .target(name: "GlideNet", dependencies: ["GlideCore"]),
        .testTarget(name: "GlideCoreTests", dependencies: ["GlideCore"]),
    ]
)
