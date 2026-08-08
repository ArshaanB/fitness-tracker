// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FitnessKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FitnessKit", targets: ["FitnessKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "FitnessKit",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "FitnessKitTests",
            dependencies: ["FitnessKit"]
        ),
    ]
)
