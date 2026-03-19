# Compiling Tailwind CSS

Integrate Tailwind CSS into your Saga build pipeline.

## Overview

Tailwind CSS needs a compilation step to scan your templates and generate a CSS file containing only the classes you use. Run this step before Saga's pipeline so the generated CSS file is available as a static asset.

## Option 1: SwiftTailwind (recommended)

[SwiftTailwind](https://github.com/loopwerk/SwiftTailwind) downloads and runs the standalone Tailwind CLI from within your Swift process. No need for Node or npm. Add it to your `Package.swift`:

```swift
.package(url: "https://github.com/loopwerk/SwiftTailwind", from: "1.0.0"),
```

Place your source CSS at `content/static/input.css`:

```css
@import "tailwindcss";
```

Then use ``Saga/beforeRead(_:)`` to run Tailwind before each build:

```swift
import SwiftTailwind

let tailwind = SwiftTailwind(version: "4.2.1")

try await Saga(input: "content", output: "deploy")
  .beforeRead { _ in
    try await tailwind.run(
      input: "content/static/input.css",
      output: "content/static/output.css",
      options: .minify
    )
  }
  .register(/* ... */)
  .run()
```

The `beforeRead` hook runs before every build cycle, including rebuilds triggered by `saga dev`. This keeps your CSS up to date as you edit templates.

Since `output.css` is written into the `content` folder, Saga copies it to the `deploy` folder automatically.

## Option 2: Shell command

If you prefer to manage Tailwind via npm, install it in your project:

```shell-session
$ npm install tailwindcss @tailwindcss/cli
```

Then use ``Saga/beforeRead(_:)`` to run the CLI before each build:

```swift
import Foundation

try await Saga(input: "content", output: "deploy")
  .beforeRead { _ in
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
      "npx", "@tailwindcss/cli",
      "-i", "content/static/input.css",
      "-o", "content/static/output.css",
      "--minify",
    ]
    try process.run()
    process.waitUntilExit()
  }
  .register(/* ... */)
  .run()
```

## With `saga dev`

Because `output.css` is written into the `content` folder, the dev server's file watcher will detect the change and trigger a rebuild. Which then regenerates `output.css`, which triggers another rebuild, and so on. Break this loop by telling `saga dev` to ignore the generated file:

```shell-session
$ saga dev --ignore output.css
```

## Cache-busting

Use ``Saga/hashed(_:)`` in your templates to serve fingerprinted CSS URLs:

```swift
link(href: Saga.hashed("/static/output.css"), rel: "stylesheet")
```

This produces a URL like `/static/output-a1b2c3d4.css` in production mode, ensuring browsers fetch the latest version after a rebuild.
