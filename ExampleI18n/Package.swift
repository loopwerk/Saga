// swift-tools-version:6.0

import PackageDescription

let package = Package(
  name: "ExampleI18n",
  platforms: [
    .macOS(.v14),
  ],
  dependencies: [
    .package(path: "../"),
    .package(url: "https://github.com/loopwerk/SagaParsleyMarkdownReader", from: "1.0.0"),
    .package(url: "https://github.com/loopwerk/SagaSwimRenderer", from: "1.0.0"),
  ],
  targets: [
    .executableTarget(
      name: "ExampleI18n",
      dependencies: [
        "Saga",
        "SagaParsleyMarkdownReader",
        "SagaSwimRenderer",
      ]
    ),
  ]
)
