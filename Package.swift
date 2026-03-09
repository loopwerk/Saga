// swift-tools-version:5.10

import PackageDescription

let package = Package(
  name: "Saga",
  platforms: [
    .macOS(.v12),
  ],
  products: [
    .library(name: "Saga", targets: ["Saga"]),
    .executable(name: "watch", targets: ["SagaWatch"]),
  ],
  dependencies: [
    .package(url: "https://github.com/kylef/PathKit", from: "1.0.1"),
    .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0"),
    // Cap swift-asn1 (transitive dep of swift-crypto) to versions that support Swift 5.10
    .package(url: "https://github.com/apple/swift-asn1.git", "1.0.0"..<"1.5.0"),
    .package(url: "https://github.com/apple/swift-argument-parser", "1.3.0"..<"1.7.0"),
    // .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.1.0"),
  ],
  targets: [
    .target(
      name: "Saga",
      dependencies: [
        "PathKit",
        .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
        .product(name: "SwiftASN1", package: "swift-asn1", condition: .when(platforms: [.linux])),
      ]
    ),
    .executableTarget(
      name: "SagaWatch",
      dependencies: [
        "PathKit",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .testTarget(
      name: "SagaTests",
      dependencies: ["Saga"]
    ),
  ]
)
