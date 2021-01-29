// swift-tools-version:5.3

import PackageDescription

let package = Package(
  name: "Examples",
  dependencies: [
    .package(path: "../"),
  ],
  targets: [
    .target(
      name: "Examples",
      dependencies: ["Saga"]),
  ]
)
