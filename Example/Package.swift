// swift-tools-version:5.3

import PackageDescription

let package = Package(
  name: "Example",
  dependencies: [
    .package(path: "../"),
    .package(url: "https://github.com/loopwerk/SagaParsleyMarkdownReader", from: "0.1.0"),
    .package(url: "https://github.com/loopwerk/SagaSwimRenderer", from: "0.1.0"),
  ],
  targets: [
    .target(
      name: "Example",
      dependencies: [
        "Saga",
        "SagaParsleyMarkdownReader",
        "SagaSwimRenderer"
      ]
    ),
  ]
)
