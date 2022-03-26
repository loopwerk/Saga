# Installation

How to set up your project with the right dependencies.


## Overview
Create a new folder and inside of it run `swift package init --type executable`, and then `open Package.swift`. Edit Package.swift to add the Saga dependency, plus a reader and optionally a renderer (see <doc:Architecture>), so that it looks something like this:

```swift
// swift-tools-version:5.5

import PackageDescription

let package = Package(
  name: "MyWebsite",
  platforms: [
    .macOS(.v12)
  ],
  dependencies: [
    .package(url: "https://github.com/loopwerk/Saga", from: "1.0.0"),
    .package(url: "https://github.com/loopwerk/SagaParsleyMarkdownReader", from: "0.5.0"),
    .package(url: "https://github.com/loopwerk/SagaSwimRenderer", from: "0.6.0"),
  ],
  targets: [
    .executableTarget(
      name: "MyWebsite",
      dependencies: [
        "Saga", 
        "SagaParsleyMarkdownReader", 
        "SagaSwimRenderer"
      ]
    )
  ]
)
```

Now you can `import Saga` and use it. You can continue with the <doc:GettingStarted> document on how to get started.


## System requirements
Saga uses async/await and as such requires at least Swift 5.5, and runs on both Mac (macOS 12) and Linux. Version 0.22.0 can be used on macOS 11 with Swift 5.2.
