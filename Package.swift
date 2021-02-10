// swift-tools-version:5.2

import PackageDescription

let package = Package(
  name: "Saga",
  platforms: [
    .macOS(.v10_15)
  ],
  products: [
    .library(
      name: "Saga",
      targets: ["Saga"]
    ),
  ],
  dependencies: [
    .package(name: "PathKit", url: "https://github.com/loopwerk/PathKit", from: "1.1.0"),
    .package(name: "Parsley", url: "https://github.com/loopwerk/Parsley", from: "0.1.0"),
    .package(name: "Codextended", url: "https://github.com/johnsundell/codextended.git", from: "0.1.0"),
    .package(name: "HTML", path: "../Swim"),
    .package(name: "Slugify", url: "https://github.com/nodes-vapor/slugify", from: "2.0.0"),
  ],
  targets: [
    .target(
      name: "Saga",
      dependencies: [
        "PathKit",
        "Parsley",
        "Codextended",
        "HTML",
        "Slugify",
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
