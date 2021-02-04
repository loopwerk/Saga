// swift-tools-version:5.3

import PackageDescription

let package = Package(
  name: "Example",
  dependencies: [
    .package(path: "../"),
  ],
  targets: [
    .target(
      name: "Example",
      dependencies: ["Saga"]),
  ]
)
