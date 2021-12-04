// swift-tools-version:5.5

import PackageDescription

let package = Package(
  name: "Example",
  platforms: [
    .macOS(.v12)
  ],
  dependencies: [
    .package(path: "../"),
    .package(path: "../../SagaParsleyMarkdownReader"),
    .package(url: "https://github.com/loopwerk/SagaSwimRenderer", from: "0.6.0"),
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
