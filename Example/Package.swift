// swift-tools-version:5.3

import PackageDescription

let package = Package(
  name: "Example",
  dependencies: [
    .package(path: "../"),
    .package(name: "ShellOut", url: "https://github.com/johnsundell/shellout.git", from: "2.3.0"),
  ],
  targets: [
    .target(
      name: "Example",
      dependencies: ["Saga", "ShellOut"]),
  ]
)
