// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CampusLensCore",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "CampusLensCore", targets: ["CampusLensCore"])],
    targets: [
        .target(name: "CampusLensCore", path: "Sources/CampusLensCore"),
        .testTarget(name: "CampusLensCoreTests", dependencies: ["CampusLensCore"], path: "Tests/CampusLensCoreTests")
    ]
)
