// swift-tools-version:5.9
import PackageDescription

// mediasoup-client-swift 0.13.2's own ios binaries, plus mac ones built from the same sources and
// webrtc m140. the frameworks are too big for git, see README.md for where they come from
let package = Package(
    name: "Mediasoup",
    platforms: [
        .iOS(.v14),
        .macOS(.v14)
    ],
    products: [
        .library(name: "Mediasoup", targets: ["Mediasoup", "WebRTC"])
    ],
    targets: [
        .binaryTarget(name: "Mediasoup", path: "Mediasoup.xcframework"),
        .binaryTarget(name: "WebRTC", path: "WebRTC.xcframework")
    ]
)
