// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "smc_webRTC",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "WebRTC",
            targets: ["WebRTC"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "WebRTC",
            url: "https://github.com/scalecode-solutions/smc_webRTC/releases/download/141.0.0/WebRTC.xcframework.zip",
            checksum: "ffbf4eee8167e7774708312ee3d4d6f28df005826d3111e6297f1d6945057deb"
        ),
    ]
)
