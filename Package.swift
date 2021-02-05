// swift-tools-version:5.3

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
    .package(name: "SwiftMarkdown", url: "https://github.com/loopwerk/SwiftMarkdown", from: "0.1.0"),
    .package(name: "Codextended", url: "https://github.com/johnsundell/codextended.git", from: "0.1.0"),
    .package(name: "Stencil", url: "https://github.com/stencilproject/Stencil.git", from: "0.14.0"),
    .package(name: "Slugify", url: "https://github.com/nodes-vapor/slugify", from: "2.0.0"),
  ],
  targets: [
    .target(
      name: "Saga",
      dependencies: [
        "SwiftMarkdown",
        "Codextended",
        "Stencil",
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
