# Programmatic Items

Create items from APIs, databases, or any async data source — without files on disk.

## Overview
Saga's pipeline is traditionally file-driven: ``Reader``s parse files into ``Item`` instances. But sometimes your content doesn't live on disk. You might want to pull data from a REST API, a database, or generate items in code.

The `register(fetch:writers:)` method lets you do exactly that. It takes an async closure that returns an array of items, and feeds them into the same writer pipeline as file-based items.

## Creating items

Use the convenience initializer on ``Item`` to create items programmatically:

```swift
let item = Item(
  title: "My Article",
  body: "<p>Hello world</p>",
  date: Date(),
  metadata: EmptyMetadata()
)
```

By default, the item's output path is derived from the slugified title: `my-article/index.html`. You can set a custom output path using the `relativeDestination` parameter:

```swift
import PathKit

let item = Item(
  title: "My Article",
  body: "<p>Hello world</p>",
  date: Date(),
  relativeDestination: Path("blog/my-article/index.html"),
  metadata: EmptyMetadata()
)
```

The `relativeDestination` controls both where the file is written and what ``Item/url`` returns, so set it to wherever you want the item to live in your site.

## Fetching from an API

Here's a complete example that fetches music videos from the iTunes API:

```swift
import Foundation
import PathKit
import Saga

struct MusicVideoMetadata: Metadata {
  let artworkUrl: String
  let previewUrl: String
}

struct ITunesResponse: Decodable {
  let results: [ITunesResult]
}

struct ITunesResult: Decodable {
  let trackCensoredName: String
  let artworkUrl100: String
  let previewUrl: String
  let releaseDate: String
}

func fetchVideos() async throws -> [Item<MusicVideoMetadata>] {
  let url = URL(string: "https://itunes.apple.com/search?term=the+beatles&media=musicVideo")!
  let (data, _) = try await URLSession.shared.data(from: url)
  let response = try JSONDecoder().decode(ITunesResponse.self, from: data)
  let dateFormatter = ISO8601DateFormatter()

  return response.results.map { result in
    let date = dateFormatter.date(from: result.releaseDate) ?? Date()
    let slug = result.trackCensoredName.slugified
    return Item(
      title: result.trackCensoredName,
      date: date,
      relativeDestination: Path("videos/\(slug)/index.html"),
      metadata: MusicVideoMetadata(
        artworkUrl: result.artworkUrl100,
        previewUrl: result.previewUrl
      )
    )
  }
}
```

## Registering the fetch step

Use `register(fetch:writers:)` just like you would a file-based `register` call:

```swift
try await Saga(input: "content", output: "deploy")
  .register(
    metadata: MusicVideoMetadata.self,
    fetch: fetchVideos,
    writers: [
      .itemWriter(swim(renderVideo)),
      .listWriter(swim(renderVideoList), output: "videos/index.html"),
    ]
  )
  .run()
  .staticFiles()
```

You can freely mix file-based and fetch-based steps. All items — regardless of how they were created — are available via ``Saga/allItems`` and passed to every writer's `allItems` parameter.

## Accessing all items

After `run()` completes, ``Saga/allItems`` contains every item from every registered step, sorted by date descending. This is useful when you need cross-step access, for example showing fetched items on a file-based page:

```swift
extension Saga {
  @discardableResult
  func createHomepage() -> Self {
    let videos = allItems.compactMap { $0 as? Item<MusicVideoMetadata> }
    // Use `videos` to generate a homepage section
    return self
  }
}
```
