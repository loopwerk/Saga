# Advanced Usage

Tips and techniques for more complex Saga setups.

## Item processors

Use an `itemProcessor` to modify items after they are read but before they are written. This is useful for transforming titles, adjusting dates, setting metadata, or any per-item logic.

```swift
func addExclamationToTitle(item: Item<EmptyMetadata>) async {
  // Do whatever you want with the Item - you can even use async functions and await them!
  item.title.append("!")
}

try await Saga(input: "content", output: "deploy")
  .register(
    readers: [.parsleyMarkdownReader],
    itemProcessor: addExclamationToTitle,
    writers: [.itemWriter(swim(renderItem))]
  )
  .run()
```

Chain multiple processors with `sequence()`:

```swift
.register(
  readers: [.parsleyMarkdownReader],
  itemProcessor: sequence(processShortcodes, fixDates, addReadingTime),
  writers: [.itemWriter(swim(renderItem))]
)
```

Since items are classes, mutations in processors are visible to all subsequent steps and writers.

> tip: See <doc:Shortcodes> for a practical example of using item processors to implement shortcode expansion.


## Template-driven pages

Create pages that are purely template-driven — no markdown file or ``Item`` needed.

Not every page on a website corresponds to a content file. Homepages, search pages, and 404 pages are often driven entirely by a template, sometimes pulling in items from other sections of the site. The ``StepBuilder/createPage(_:using:)`` method lets you render these pages without needing a markdown file or ``Item``.

```swift
try await Saga(input: "content", output: "deploy")
  .register(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.parsleyMarkdownReader],
    writers: [
      .itemWriter(swim(renderArticle)),
      .listWriter(swim(renderArticles)),
    ]
  )
  .createPage("index.html", using: swim(renderHome))
  .createPage("404.html", using: swim(render404))
  .run()
```

The renderer receives a ``PageRenderingContext`` with access to ``PageRenderingContext/allItems`` (all items across all processing steps) and ``PageRenderingContext/outputPath``.

Use ``StepBuilder/createPage(_:using:)`` when the page has no corresponding content file and is purely template-driven. Use `register` when content comes from files on disk or a programmatic data source and you need the full ``Item`` pipeline.

> tip: See <doc:GeneratingSitemaps> and <doc:AddingSearch> for practical examples of template-driven pages.


## Custom processing steps

Register custom processing steps for logic outside the standard pipeline: generate images, build a search index, or run any custom logic as part of your build. The closure runs during the [write phase](doc:Architecture), after all items have been read and sorted. Use `register` with a trailing closure:

```swift
try await Saga(input: "content", output: "deploy")
  .register(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.parsleyMarkdownReader],
    writers: [.itemWriter(swim(renderArticle))]
  )
  .register { saga in
    let articles = saga.allItems.compactMap { $0 as? Item<ArticleMetadata> }
    for article in articles {
      let destination = (saga.outputPath + article.relativeDestination.parent()).string + ".png"
      // generate an image and write it to `destination`
    }
  }
  .run()
```

The closure receives the ``Saga`` instance with access to ``Saga/allItems``, ``Saga/outputPath``, and everything else you need.

> tip: You can check the [source of loopwerk.io](https://github.com/loopwerk/loopwerk.io) for more inspiration.


## Programmatic items

Saga's pipeline is traditionally file-driven: ``Reader``s parse files into ``Item`` instances. But sometimes your content doesn't live on disk. The `register(fetch:writers:)` method takes an async closure that returns an array of items, feeding them into the same writer pipeline as file-based items.

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
import SagaPathKit

let item = Item(
  title: "My Article",
  body: "<p>Hello world</p>",
  date: Date(),
  relativeDestination: Path("blog/my-article/index.html"),
  metadata: EmptyMetadata()
)
```

You can freely mix file-based and fetch-based steps. All items — regardless of how they were created — are available via ``Saga/allItems`` and passed to every writer's `allItems` parameter.

> tip: See <doc:FetchingFromAPIs> for a complete example fetching GitHub repositories and rendering them as portfolio pages.


## Nested subfolder processing

When you have content organized into subfolders and want each subfolder processed independently — with its own scoped `items` array, `previous`/`next` navigation, and writers — use the `nested:` parameter:

```swift
try await Saga(input: "content", output: "deploy")
  .register(
    folder: "photos",
    nested: { nested in
      nested.register(
        metadata: PhotoMetadata.self,
        readers: [.parsleyMarkdownReader],
        writers: [
          .listWriter(swim(renderPhotoList)),
          .itemWriter(swim(renderPhoto)),
        ]
      )
    }
  )
  .run()
```

Given a directory layout like:

```
content/
  photos/
    vacation/
      photo1.md
      photo2.md
    birthday/
      photo3.md
      photo4.md
```

Saga processes `photos/vacation` and `photos/birthday` independently. Each subfolder gets its own scoped `items` array, so a `listWriter` produces one index per subfolder and `previous`/`next` links stay within the subfolder.

Without `nested:`, `folder: "photos"` would treat every file under `photos/` as part of a single flat collection.

### Accessing subfolders from outer writers

Saga creates a synthetic ``Item`` per subfolder, with `title` set to the subfolder name and `children` wired to the nested items. Add outer `writers` to render an overview page:

```swift
.register(
  folder: "photos",
  writers: [
    .listWriter(swim(renderAlbumIndex)),
  ],
  nested: { nested in
    nested.register(
      metadata: PhotoMetadata.self,
      readers: [.parsleyMarkdownReader],
      writers: [
        .listWriter(swim(renderPhotoList)),
      ]
    )
  }
)
```

In the template, use `children()` to access the nested items:

```swift
func renderAlbumIndex(context: ItemsRenderingContext<EmptyMetadata>) -> Node {
  context.items.map { album in
    let photos: [Item<PhotoMetadata>] = album.children()
    a(href: album.url) {
      h2 { album.title }
      p { "\(photos.count) photos" }
    }
  }
}
```

### Parent/child with different readers

When the parent and child items use different readers and metadata types, specify `readers` and `metadata` on both the outer and nested registrations:

```swift
.register(
  folder: "photos",
  metadata: AlbumMetadata.self,
  readers: [.parsleyMarkdownReader],
  writers: [
    .listWriter(swim(renderAlbums)),
    .itemWriter(swim(renderAlbum)),
  ],
  nested: { nested in
    nested.register(
      metadata: PhotoMetadata.self,
      readers: [.imageReader],
      writers: [
        .itemWriter(swim(renderPhoto)),
      ]
    )
  }
)
```

Here the outer readers create real parent items from `index.md` files, and `children`/`parent` relationships are wired automatically:

```swift
// In a nested item's template
let album: Item<AlbumMetadata>? = context.item.parent()

// In a parent item's template
let photos: [Item<PhotoMetadata>] = context.item.children()
```

> tip: See <doc:PhotoGalleries> for a complete photo gallery example with album pages and per-album navigation.


## Post-processing output

Use ``Saga/postProcess(_:)`` to transform every file before it's written. Multiple calls stack. The transform receives the rendered content and the relative output path.

```swift
try await Saga(input: "content", output: "deploy")
  .register(
    metadata: EmptyMetadata.self,
    readers: [.parsleyMarkdownReader],
    writers: [.itemWriter(swim(renderPage))]
  )
  .postProcess { content, path in
    guard !isDev, path.extension == "html" else { return content }
    return minifyHTML(content)
  }
  .run()
```

> tip: See <doc:HTMLMinification> for a step-by-step setup guide.


## Cache-busting with hashed()

The ``hashed(_:)`` function takes a path like `/static/output.css` and returns `/static/output-a1b2c3d4.css`, where the hash is derived from the file's contents. Saga automatically copies the hashed file to the output folder.

Call ``hashed(_:)`` from any renderer to produce fingerprinted asset URLs:

```swift
func renderPage(context: ItemRenderingContext<EmptyMetadata>) -> Node {
  html {
    head {
      link(href: hashed("/static/style.css"), rel: "stylesheet")
    }
    body {
      Node.raw(context.item.body)
    }
  }
}
```

> note: In dev mode (when using `saga dev`), ``hashed(_:)`` returns the path unchanged to keep filenames stable for auto-reload. See <doc:GettingStarted> for more on dev mode.
