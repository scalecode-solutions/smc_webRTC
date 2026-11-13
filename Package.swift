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
            url: "https://github.com/scalecode-solutions/smc_webRTC/releases/download/158.2.0/WebRTC.xcframework.zip",
            checksum: "50b72979561c142ef026ab95f92e5635a4d3cbad38e1a108f19e11329c71b1b2"
        ),
    ]
)
