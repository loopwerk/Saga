// swift-tools-version:5.3

import PackageDescription

let package = Package(
  name: "Example",
  platforms: [
    .macOS(.v10_15)
  ],
  dependencies: [
    .package(path: "../"),
  ],
  targets: [
    .target(
      name: "Example",
      dependencies: ["Saga"]),
  ]
)
