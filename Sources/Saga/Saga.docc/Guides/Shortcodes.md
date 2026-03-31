# Implementing Shortcodes

Replace template strings in your content with rendered HTML using item processors.

## Overview

Shortcodes let you embed dynamic content in your Markdown files using a simple syntax like `{{youtube id="dQw4w9WgXcQ"}}`. Since Saga's item processors run after the reader parses Markdown into HTML, you can search and replace these patterns in the item's `body`.

## Define a shortcode syntax

Choose a pattern that won't conflict with markdown. A common choice is double curly braces:

```text
---
title: My Article
---

Check out this video:

{{youtube id="dQw4w9WgXcQ"}}

And here's a note:

{{note}}
This is important information.
{{/note}}
```

## Write an item processor

Create a processor that finds and replaces shortcode patterns:

```swift
import Foundation
import Saga

func processShortcodes(item: Item<ArticleMetadata>) async {
  // Self-closing shortcodes: {{youtube id="..."}}
  item.body = item.body.replacingOccurrences(
    of: #"\{\{youtube id="([^"]+)"\}\}"#,
    with: """
      <div class="video-embed">
        <iframe src="https://www.youtube.com/embed/$1" \
        frameborder="0" allowfullscreen></iframe>
      </div>
      """,
    options: .regularExpression
  )

  // Block shortcodes: {{note}}...{{/note}}
  item.body = item.body.replacingOccurrences(
    of: #"\{\{note\}\}(.*?)\{\{/note\}\}"#,
    with: "<aside class=\"note\">$1</aside>",
    options: [.regularExpression, .dotMatchesLineSeparators]
  )
}
```

## Register the processor

Pass your shortcode processor as the `itemProcessor`, or chain it with other processors using ``Saga/sequence(_:)``:

```swift
try await Saga(input: "content", output: "deploy")
  .register(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.parsleyMarkdownReader],
    itemProcessor: processShortcodes,
    writers: [.itemWriter(swim(renderArticle))]
  )
  .run()
```

To combine multiple processors:

```swift
try await Saga(input: "content", output: "deploy")
  .register(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.parsleyMarkdownReader],
    itemProcessor: sequence(processShortcodes, anotherProcessor),
    writers: [.itemWriter(swim(renderArticle))]
  )
  .run()
```

> Tip: For more complex transformations that need to work with the HTML DOM rather than string replacement, consider using [SagaUtils](https://github.com/loopwerk/SagaUtils) which provides SwiftSoup-based HTML transformations.
