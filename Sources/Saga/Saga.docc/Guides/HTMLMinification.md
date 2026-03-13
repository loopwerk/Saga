# HTML Minification

Minify your HTML output to reduce file sizes.

## Overview

Saga's ``Saga/postProcess(_:)`` method lets you transform every file before it's written. Combined with an HTML minification library, you can strip whitespace, remove comments, and reduce your output size with minimal effort.

## Setup

Add an HTML minification library to your `Package.swift`. [Bonsai](https://github.com/loopwerk/Bonsai) is a lightweight option:

```swift
.package(url: "https://github.com/loopwerk/Bonsai", from: "1.0.0"),
```

## Add post-processing

Add a ``Saga/postProcess(_:)`` step to your Saga pipeline:

```swift
import Bonsai

try await Saga(input: "content", output: "deploy")
  .register(...)
  .postProcess { html, path in
    guard !isDev else { return html }
    return Bonsai.minifyHTML(html)
  }
  .run()
```

The `isDev` check skips minification during development for faster rebuilds and easier debugging.

## Selective processing

The second parameter is the relative output path, so you can limit minification to HTML files:

```swift
.postProcess { content, path in
  guard !isDev, path.extension == "html" else { return content }
  return Bonsai.minifyHTML(content)
}
```
