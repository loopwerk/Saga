// swift-tools-version:5.5

import PackageDescription

let package = Package(
  name: "Saga",
  platforms: [
    .macOS(.v12)
  ],
  products: [
    .library(name: "Saga", targets: ["Saga"]),
    .executable(name: "watch", targets: ["SagaCLI"])
  ],
  dependencies: [
    .package(url: "https://github.com/loopwerk/PathKit", from: "1.1.0"),
    .package(url: "https://github.com/JohnSundell/Codextended.git", from: "0.1.0"),
  ],
  targets: [
    .target(
      name: "Saga",
      dependencies: [
        "PathKit",
        "Codextended",
      ]
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
