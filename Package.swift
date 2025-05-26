// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "JSONLD",
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
