# Custom Feed Formats

Build your own feed renderer, using JSON Feed as an example.

## Overview

Saga ships with a built-in ``Saga/atomFeed(title:author:baseURL:summary:image:dateKeyPath:)`` renderer, but you can create renderers for any feed format. This guide walks you through building a [JSON Feed](https://www.jsonfeed.org) renderer to show the pattern.

A renderer is a function that returns a `@Sendable (Context) -> String` closure — the same signature used by the built-in Atom renderer. The closure receives a rendering context with the items and output path, and returns the feed content as a string.

## Defining the feed structure

JSON Feed's structure maps naturally to Swift's `Codable`. Define structs for the feed and its entries:

```swift
struct JSONFeedOutput: Codable {
  let version: String
  let title: String
  let homePageUrl: String
  let feedUrl: String
  let authors: [JSONFeedAuthor]?
  let items: [JSONFeedItem]
}

struct JSONFeedAuthor: Codable {
  let name: String
}

struct JSONFeedItem: Codable {
  let id: String
  let url: String
  let title: String
  let contentHtml: String
  let datePublished: String
  let authors: [JSONFeedAuthor]?
}
```

Using `JSONEncoder` with `.convertToSnakeCase`, these property names automatically become the snake_case keys that the JSON Feed spec requires (`homePageUrl` → `home_page_url`, `contentHtml` → `content_html`, etc).

## Writing the renderer

The renderer is a function that uses the existing `AtomContext` protocol — it provides `items` and `outputPath`, which is everything a feed needs:

```swift
import Foundation
import Saga

func jsonFeed<Context: AtomContext>(
  title: String,
  baseURL: URL,
  author: String? = nil
) -> @Sendable (Context) -> String {
  return { context in
    let dateFormatter = ISO8601DateFormatter()
    let feedAuthor = author.map { [JSONFeedAuthor(name: $0)] }

    let feed = JSONFeedOutput(
      version: "https://jsonfeed.org/version/1.1",
      title: title,
      homePageUrl: baseURL.absoluteString,
      feedUrl: baseURL.appendingPathComponent(context.outputPath.string).absoluteString,
      authors: feedAuthor,
      items: context.items.map { item in
        JSONFeedItem(
          id: baseURL.appendingPathComponent(item.url).absoluteString,
          url: baseURL.appendingPathComponent(item.url).absoluteString,
          title: item.title,
          contentHtml: item.body,
          datePublished: dateFormatter.string(from: item.date),
          authors: feedAuthor
        )
      }
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let data = try! encoder.encode(feed)
    return String(data: data, encoding: .utf8) ?? ""
  }
}
```

## Using the renderer

Wire it into your pipeline with a `listWriter`, just like the built-in Atom feed:

```swift
.register(
  folder: "articles",
  metadata: ArticleMetadata.self,
  readers: [.parsleyMarkdownReader],
  writers: [
    .itemWriter(swim(renderArticle)),
    .listWriter(swim(renderArticles)),

    // Built-in Atom feed
    .listWriter(Saga.atomFeed(
      title: "My Site",
      author: "Author Name",
      baseURL: siteURL
    ), output: "feed.xml"),

    // Custom JSON Feed
    .listWriter(jsonFeed(
      title: "My Site",
      baseURL: siteURL,
      author: "Author Name"
    ), output: "feed.json"),
  ]
)
```

## Applying the pattern to other formats

The same approach works for any output format:

1. Define your output structure (structs, XML builder, or plain string interpolation)
2. Write a function that returns `@Sendable (Context) -> String`
3. Use `AtomContext` (or another rendering context) to access items
4. Wire it up with `listWriter` or `tagWriter`

The key insight is that a "renderer" in Saga is just a function from context to string. There's no special protocol to adopt or plugin system to hook into.
