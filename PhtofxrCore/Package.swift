// swift-tools-version: 6.0
import PackageDescription

// Pure Foundation: no PhotoKit, UIKit or SwiftUI, so `swift test` runs on Linux too.
let package = Package(
    name: "PhtofxrCore",
    platforms: [
        .iOS("27.2"),
        .macOS(.v15),
    ],
    products: [
        .library(name: "PhtofxrCore", targets: ["PhtofxrCore"]),
    ],
    targets: [
        .target(name: "PhtofxrCore"),
        .testTarget(name: "PhtofxrCoreTests", dependencies: ["PhtofxrCore"]),
    ]
)
