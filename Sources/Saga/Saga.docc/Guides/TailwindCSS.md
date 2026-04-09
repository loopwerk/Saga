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
  // Compile tailwind to output.css
  .beforeRead { _ in
    try await tailwind.run(
      input: "content/static/input.css",
      output: "content/static/output.css",
      options: .minify
    )
  }

  // Don't trigger a rebuild when output.css changes, 
  // otherwise we get into an endless loop
  .ignoreChanges("output.css")
  
  // The rest of the pipeline as normal...
  .register(/* ... */)
  .run()
```

The `beforeRead` hook runs before every build cycle, including rebuilds triggered by `saga dev`. This keeps your CSS up to date as you edit templates.

Since `output.css` is written into the `content` folder, Saga copies it to the `deploy` folder automatically.

### Optional performance improvement

Instead of always compiling the CSS on every single build, we can be a bit smarter and only do this when a CSS file or a template file was changed:

```swift
try await Saga(input: "content", output: "deploy")
  // Compile tailwind to output.css
  .beforeRead { saga in
    // It needs to be a css file or a template file, otherwise skip it
    if let path = saga.buildReason.changedFile(),
       path.extension != "css", 
       !path.components.contains("templates")
    {
      return
    }

    try await tailwind.run(
      input: "content/static/input.css",
      output: "content/static/output.css",
      options: .minify
    )
  }
  
  // And the rest...
```

## Option 2: Shell command

If you prefer to manage Tailwind via npm, install it in your project:

```shell-session
$ npm install tailwindcss @tailwindcss/cli
```

Then instead of running Tailwind as part of your Saga pipeline you can start its own watcher:

```shell-session
tailwindcss -i ./content/static/input.css -o ./content/static/output.css --minify --watch
```

This is faster than option 1 because Tailwind does its own incremental compilation (especially noticeable with Tailwind CSS v3). However, it requires Node and npm, a separate terminal process alongside `saga dev`, and extra CI/CD setup, whereas SwiftTailwind keeps everything in one Swift file with no external dependencies.

## Cache-busting

Use ``Saga/hashed(_:)`` in your templates to serve fingerprinted CSS URLs:

```swift
link(href: Saga.hashed("/static/output.css"), rel: "stylesheet")
```

This produces a URL like `/static/output-a1b2c3d4.css` in production mode, ensuring browsers fetch the latest version after a rebuild.
