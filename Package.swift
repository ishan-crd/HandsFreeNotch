// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "HandsFreeNotch",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HandsFreeNotch", targets: ["HandsFreeNotch"]),
        .library(name: "HandsFreeNotchCore", targets: ["HandsFreeNotchCore"]),
    ],
    targets: [
        // Everything that has no UI: speech, intent routing, and the actions that run on the Mac.
        .target(
            name: "HandsFreeNotchCore",
            path: "Sources/HandsFreeNotchCore"
        ),
        // The notch app itself.
        .executableTarget(
            name: "HandsFreeNotch",
            dependencies: ["HandsFreeNotchCore"],
            path: "Sources/HandsFreeNotch"
        ),
        .testTarget(
            name: "HandsFreeNotchCoreTests",
            dependencies: ["HandsFreeNotchCore"],
            path: "Tests/HandsFreeNotchCoreTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
