# Advanced Usage

Tips and techniques for more complex Saga setups.


## Build hooks

Use ``Saga/beforeRead(_:)`` and ``Saga/afterWrite(_:)`` to run custom logic before or after each build cycle. These hooks run on every build, including rebuilds triggered by `saga dev`.

```swift
try await Saga(input: "content", output: "deploy")
  .beforeRead { saga in
    // Runs before the read phase, e.g. compile CSS
  }
  .register(/* ... */)
  .afterWrite { saga in
    // Runs after the write phase, e.g. index for search
  }
  .run()
```

You can register multiple hooks of the same type — they run in the order they were added. Each hook receives the ``Saga`` instance.

> Tip: See <doc:TailwindCSS> for a `beforeRead` example and <doc:AddingSearch> for an `afterWrite` example.


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

Chain multiple processors with ``Saga/sequence(_:)``:

```swift
.register(
  readers: [.parsleyMarkdownReader],
  itemProcessor: sequence(processShortcodes, fixDates, addReadingTime),
  writers: [.itemWriter(swim(renderItem))]
)
```

> Tip: See <doc:Shortcodes> for a practical example of using item processors to implement shortcode expansion.


## Template-driven pages

Create pages that are purely template-driven — no Markdown file or ``Item`` needed.

Not every page on a website corresponds to a content file. Homepages, search pages, and 404 pages are often driven entirely by a template, sometimes pulling in items from other sections of the site. The ``StepBuilder/createPage(_:using:)`` method lets you render these pages without needing a Markdown file.

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

> Note: In dev mode (when using `saga dev`), ``Saga/hashed(_:)`` returns the path unchanged to keep filenames stable for auto-reload.