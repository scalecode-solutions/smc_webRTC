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
            url: "https://github.com/scalecode-solutions/smc_webRTC/releases/download/141.2.0/WebRTC.xcframework.zip",
            checksum: "0ac4086c5c1c7a08468ba3b91a989fbd9ae4d5a82d6346bd7ce532c24c2d99a4"
        ),
    ]
)
