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
            url: "https://github.com/scalecode-solutions/smc_webRTC/releases/download/141.1.0/WebRTC.xcframework.zip",
            checksum: "c50ec3639be87a6c6cb458dfe85a2fa9587495c5e3c355dedb464fa70517fffc"
        ),
    ]
)
