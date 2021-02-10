// swift-tools-version:5.3

import PackageDescription

let package = Package(
  name: "Example",
  platforms: [
    .macOS(.v10_15)
  ],
  dependencies: [
    .package(path: "../"),
    .package(url: "https://github.com/loopwerk/SagaSwimRenderer", from: "0.1.0")
  ],
  targets: [
    .target(
      name: "Example",
      dependencies: [
        "Saga",
        "SagaSwimRenderer"
      ]
    ),
  ]
)
