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
            url: "https://github.com/scalecode-solutions/smc_webRTC/releases/download/147.2.0/WebRTC.xcframework.zip",
            checksum: "ac697921b9f4354136163cc4030136c37f9580d31ff552f59b10358f3d767ab2"
        ),
    ]
)
