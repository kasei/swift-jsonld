// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "JSONLD",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
    ],
    products: [
        .library(
            name: "JSONLD",
            targets: ["JSONLD"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
		.target( name: "JSONLD", dependencies: []),
		.target( name: "jsonld-expand", dependencies: ["JSONLD", "ArgumentParser"]),
		.testTarget( name: "JSONLDTests", dependencies: ["JSONLD"]),
    ]
)
