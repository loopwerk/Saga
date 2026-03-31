# Syntax Highlighting

Add server-side syntax highlighting to code blocks using Moon.

## Overview

When your Markdown content includes fenced code blocks, they're rendered as plain `<pre><code>` elements by default. [Moon](https://github.com/loopwerk/Moon) adds syntax highlighting using Prism, but at build time, so visitors see highlighted code without the need to load any client-side JavaScript.

## Setup

Add Moon to your `Package.swift`:

```swift
.package(url: "https://github.com/loopwerk/Moon", from: "1.0.0"),
```

And add it to your target's dependencies:

```swift
.executableTarget(
  name: "Example",
  dependencies: [
    ...,
    "Moon",
  ]
),
```

## Highlight code blocks

Call `Moon.shared.highlightCodeBlocks(in:)` on an item's body when rendering it. You can either do this directly in your templates, or with an item processor:

```swift
import Moon

func syntaxHighlight<M>(item: Item<M>) {
  item.body = syntaxHighlighter.highlightCodeBlocks(in: item.body)
}

try await Saga(input: "content", output: "deploy")
  .register(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.parsleyMarkdownReader],
    itemProcessor: syntaxHighlight, // <- use the item processor
    writers: [
      .itemWriter(swim(renderArticle)),
      .listWriter(swim(renderArticles)),
    ]
  )
  .run()
```

Now the code blocks in your Markdown content, annotated with the programming language, will be properly sytax-highlighted.

~~~text
# This is my article

With some code:

```swift
print("hello world")
```
~~~

## Add a stylesheet

Moon generates markup compatible with [Prism](https://prismjs.com) CSS themes. Add a Prism stylesheet to your site's `<head>`:

```swift
link(rel: "stylesheet", href: Saga.hashed("/static/prism.css"))
```

You can grab a theme from the [Prism website](https://prismjs.com) or [themes repo](https://github.com/PrismJS/prism-themes).
