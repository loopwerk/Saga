# Open External Links in New Tabs

Add `target="_blank"` to links pointing to other websites.

## Overview

Markdown gives you no control over how a link opens: `[Saga](https://github.com/loopwerk/Saga)` always becomes a plain `<a href="...">`. Since item processors run after the reader has turned Markdown into HTML, you can rewrite those links before they're written to disk.

[SagaUtils](https://github.com/loopwerk/SagaUtils) ships a `processExternalLinks` transformation that does exactly this: every link whose `href` starts with `http://` or `https://` gets `target="_blank"` and `rel="noopener"`.

## Setup

Add SagaUtils to your `Package.swift`:

```swift
.package(url: "https://github.com/loopwerk/SagaUtils", from: "1.0.0"),
```

## Register the processor

SagaUtils' transformations are combined with `swiftSoupProcessor`, which parses the item's body once, applies each transformation in order, and serializes it back:

```swift
import SagaUtils

try await Saga(input: "content", output: "deploy")
  .register(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.parsleyMarkdownReader],
    itemProcessor: swiftSoupProcessor(processExternalLinks),
    writers: [.itemWriter(swim(renderArticle))]
  )
  .run()
```

Relative links like `/articles/my-first-article/` are left alone. If you link to your own site with absolute URLs, those are treated as external too. See below for how to exclude your own domain.

## Combining with other processors

To mix this with other processors, use ``Saga/sequence(_:)``:

```swift
let articleProcessor = sequence(
  swiftSoupProcessor(convertAsides, processExternalLinks),
  publicationDateInFilename
)
```

## Writing your own version

`processExternalLinks` is deliberately simple. If you want different `rel` values, or you link to your own site with absolute URLs and don't want those to open in a new tab, write your own transformation. Any `(Document, Item<M>) throws -> Void` function can be passed to `swiftSoupProcessor`:

```swift
import SagaUtils
import SwiftSoup

func openExternalLinksInNewTab<M>(_ doc: Document, item: Item<M>) throws {
  for link in try doc.select("a[href]") {
    let href = try link.attr("href")
    guard let host = URL(string: href)?.host, host != "www.example.com" else {
      continue
    }
    try _ = link.attr("target", "_blank")
    try _ = link.attr("rel", "noopener")
  }
}
```

Relative links have no host, so they're skipped by the `guard`.
