// swift-tools-version:5.5

import PackageDescription

let package = Package(
  name: "Saga",
  platforms: [
    .macOS(.v12),
  ],
  products: [
    .library(name: "Saga", targets: ["Saga"]),
    .executable(name: "saga", targets: ["SagaCLI"]),
    .executable(name: "watch", targets: ["SagaWatch"]),
  ],
  dependencies: [
    .package(url: "https://github.com/kylef/PathKit", from: "1.0.1"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    .package(url: "https://github.com/apple/swift-nio", from: "2.65.0"),
    // .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.1.0"),
  ],
  targets: [
    .target(
      name: "Saga",
      dependencies: ["PathKit"]
    ),
    .executableTarget(
      name: "SagaCLI",
      dependencies: [
        "PathKit",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOPosix", package: "swift-nio"),
        .product(name: "NIOHTTP1", package: "swift-nio"),
      ]
    ),
    .executableTarget(
      name: "SagaWatch",
      dependencies: [
        "PathKit",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .testTarget(
      name: "SagaTests",
      dependencies: ["Saga"]
    ),
  ]
)
