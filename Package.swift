// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BubblesAutoclicker",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "BubblesCore", targets: ["BubblesCore"]),
        .executable(name: "BubblesAutoclicker", targets: ["BubblesAutoclicker"])
    ],
    targets: [
        .target(name: "BubblesCore"),
        .executableTarget(
            name: "BubblesAutoclicker",
            dependencies: ["BubblesCore"],
            path: "Sources/BubblesAutoclicker"
        ),
        .testTarget(name: "BubblesCoreTests", dependencies: ["BubblesCore"])
    ]
)
