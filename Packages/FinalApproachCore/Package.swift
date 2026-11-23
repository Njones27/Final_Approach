// swift-tools-version: 6.0

import PackageDescription

// Pure Swift domain logic for Final Approach. This package must not import
// Apple-only frameworks, so its tests can run on Linux in GitHub Actions.
let package = Package(
    name: "FinalApproachCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "FinalApproachCore", targets: ["FinalApproachCore"]),
    ],
    targets: [
        .target(name: "FinalApproachCore"),
        .testTarget(
            name: "FinalApproachCoreTests",
            dependencies: ["FinalApproachCore"]
        ),
    ]
)
