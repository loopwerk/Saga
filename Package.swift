// swift-tools-version:6.0

import PackageDescription

let package = Package(
  name: "Saga",
  platforms: [
    .macOS(.v14),
  ],
  products: [
    .library(name: "Saga", targets: ["Saga"]),
  ],
  dependencies: [
    .package(url: "https://github.com/loopwerk/SagaPathKit", from: "1.6.1"),
    .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0"),
  ],
  targets: [
    .target(
      name: "Saga",
      dependencies: [
        "SagaPathKit",
        .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
      ]
    ),
    .testTarget(
      name: "SagaTests",
      dependencies: ["Saga"]
    ),
  ]
)
