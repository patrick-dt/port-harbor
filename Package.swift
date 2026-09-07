// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PortHarbor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PortHarbor", targets: ["PortHarbor"])
    ],
    targets: [
        .executableTarget(
            name: "PortHarbor",
            path: "Sources/PortHarbor"
        ),
        .testTarget(
            name: "PortHarborTests",
            dependencies: ["PortHarbor"],
            path: "Tests/PortHarborTests"
        )
    ]
)

