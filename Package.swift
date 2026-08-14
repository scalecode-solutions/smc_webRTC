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
            url: "https://github.com/scalecode-solutions/smc_webRTC/releases/download/152.2.0/WebRTC.xcframework.zip",
            checksum: "c097f7ae8da2bf76b128fd936d0be8219f869383931e32cf7aec2d9d869f5e35"
        ),
    ]
)
