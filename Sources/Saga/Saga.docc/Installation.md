# Installation

How to set up a new Saga project.


## Installing the CLI

**Via [Homebrew](https://brew.sh):**

```
$ brew install loopwerk/tap/saga
```

**Via [Mint](https://github.com/yonaskolb/Mint):**

```
$ mint install loopwerk/Saga
```


## Quick start

The easiest way to create a new project is with the `saga` CLI:

```
$ saga init mysite
$ cd mysite
$ saga dev
```

This scaffolds a complete project with articles, tags, Swim templates, and a stylesheet. The `saga dev` command builds your site, starts a development server at `http://localhost:3000`, and auto-reloads the browser when you make changes.


## Manual setup

If you prefer to set things up yourself, create a new folder and inside of it run `swift package init --type executable`, and then `open Package.swift`. Edit Package.swift to add the Saga dependency, plus a reader and optionally a renderer (see <doc:Architecture>), so that it looks something like this:

```swift
// swift-tools-version:5.5

import PackageDescription

let package = Package(
  name: "MyWebsite",
  platforms: [
    .macOS(.v12)
  ],
  dependencies: [
    .package(url: "https://github.com/loopwerk/Saga", from: "2.0.0"),
    .package(url: "https://github.com/loopwerk/SagaParsleyMarkdownReader", from: "1.0.0"),
    .package(url: "https://github.com/loopwerk/SagaSwimRenderer", from: "1.0.0"),
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
Saga requires at least Swift 5.5, and runs on both Mac (macOS 12) and Linux.
