// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacFeine",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacFeine", targets: ["MacFeine"])
    ],
    targets: [
        .executableTarget(
            name: "MacFeine",
            path: "Sources/MacFeine"
        )
    ]
)
