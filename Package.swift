// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CableKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14), .macCatalyst(.v17)],
    products: [
        .library(name: "CableKit", targets: ["CableKit"])
    ],
    targets: [
        .target(name: "CableKit", resources: [.process("Resources")]),

        .testTarget(name: "CableKitTests", dependencies: ["CableKit"]),
    ],
    swiftLanguageModes: [.v6],
)
