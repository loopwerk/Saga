// swift-tools-version:5.2

import PackageDescription

let package = Package(
  name: "Saga",
  products: [
    .library(
      name: "Saga",
      targets: ["Saga"]
    ),
  ],
  dependencies: [
    .package(name: "PathKit", url: "https://github.com/loopwerk/PathKit", from: "1.1.0"),
    .package(name: "Codextended", url: "https://github.com/johnsundell/codextended.git", from: "0.1.0"),
  ],
  targets: [
    .target(
      name: "Saga",
      dependencies: [
        "PathKit",
        "Codextended",
      ]
    ),
    .testTarget(
      name: "SagaTests",
      dependencies: [
        "Saga",
      ]
    ),
  ]
)
