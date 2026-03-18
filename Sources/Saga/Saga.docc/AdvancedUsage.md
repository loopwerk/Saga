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

Chain multiple processors with `Saga.sequence()`:

```swift
.register(
  readers: [.parsleyMarkdownReader],
  itemProcessor: Saga.sequence(processShortcodes, fixDates, addReadingTime),
  writers: [.itemWriter(swim(renderItem))]
)
```

Since items are classes, mutations in processors are visible to all subsequent steps and writers.

> Tip: See <doc:Shortcodes> for a practical example of using item processors to implement shortcode expansion.


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

> Tip: See <doc:GeneratingSitemaps> and <doc:AddingSearch> for practical examples of template-driven pages.


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

> Tip: You can check the [source of loopwerk.io](https://github.com/loopwerk/loopwerk.io) for more inspiration.


## Programmatic items

Not all content lives on disk. The ``StepBuilder/register(metadata:fetch:cacheKey:itemProcessor:sorting:writers:)`` method takes an async closure that returns an array of items, feeding them into the same writer pipeline as file-based content. You can freely mix file-based and fetch-based steps.

> Tip: See <doc:FetchingFromAPIs> for a complete example fetching GitHub repositories and rendering them as portfolio pages.


## Nested subfolder processing

When you have content organized into subfolders and want each subfolder processed independently, with its own scoped `items` array, `previous`/`next` navigation, and writers, use the `nested:` parameter. Each subfolder gets its own processing scope, so writers and navigation stay within that subfolder.

> Tip: See <doc:PhotoGalleries> for a complete example building photo galleries with nested processing, album pages, and per-album navigation.


## Custom output URLs with slug

By default, an item's output path mirrors its source filename. Set `slug` in frontmatter to override it:

```yaml
---
slug: my-custom-url
---
# Page Title
```

This writes the item to `my-custom-url/index.html` (or `my-custom-url.html` with `.keepAsFile` write mode) instead of deriving the path from the filename. The `slug` value is slugified automatically.

This is useful for giving pages human-friendly or localized URLs without renaming the source file. For i18n usage, see <doc:Internationalization>.


## Cache-busting with Saga.hashed()

The ``Saga/hashed(_:)`` function takes a path like `/static/output.css` and returns `/static/output-a1b2c3d4.css`, where the hash is derived from the file's contents. Saga automatically copies the hashed file to the output folder.

Call ``Saga/hashed(_:)`` from any renderer to produce fingerprinted asset URLs:

```swift
func renderPage(context: ItemRenderingContext<EmptyMetadata>) -> Node {
  html {
    head {
      link(href: Saga.hashed("/static/style.css"), rel: "stylesheet")
    }
    body {
      Node.raw(context.item.body)
    }
  }
}
```

> Note: In dev mode (when using `saga dev`), ``Saga/hashed(_:)`` returns the path unchanged to keep filenames stable for auto-reload. See <doc:GettingStarted> for more on dev mode.
