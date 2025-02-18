// swift-tools-version:5.5

import PackageDescription

let package = Package(
  name: "Saga",
  platforms: [
    .macOS(.v12),
  ],
  products: [
    .library(name: "Saga", targets: ["Saga"]),
    .executable(name: "watch", targets: ["SagaCLI"]),
  ],
  dependencies: [
    .package(url: "https://github.com/kylef/PathKit", from: "1.0.1"),
    // .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.1.0"),
  ],
  targets: [
    .target(
      name: "Saga",
      dependencies: ["PathKit"]
    ),
    .executableTarget(
      name: "SagaCLI",
      dependencies: ["PathKit"]
    ),
    .testTarget(
      name: "SagaTests",
      dependencies: ["Saga"]
    ),
  ]
)
