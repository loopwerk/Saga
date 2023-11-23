// swift-tools-version:5.5

import PackageDescription

let package = Package(
  name: "Example",
  platforms: [
    .macOS(.v12)
  ],
  dependencies: [
    .package(path: "../"),
    .package(url: "https://github.com/loopwerk/SagaParsleyMarkdownReader", from: "0.5.0"),
    .package(url: "https://github.com/loopwerk/SagaSwimRenderer", from: "0.7.0"),
  ],
  targets: [
    .executableTarget(
      name: "Example",
      dependencies: [
        "Saga",
        "SagaParsleyMarkdownReader",
        "SagaSwimRenderer"
      ]
    ),
  ]
)
