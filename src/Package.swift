// swift-tools-version: 6.2
// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Stack",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Stack", targets: ["Stack"])
    ],
    targets: [
        .executableTarget(
            name: "Stack",
            exclude: ["en.lproj"]
        )
    ]
)
