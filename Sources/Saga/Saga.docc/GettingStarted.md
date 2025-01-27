# Getting Started with Saga

An overview of how to configure Saga to render your pages and articles.


## Overview
Let's start with the most basic example: rendering all Markdown files to HTML.

```swift
import Saga
import SagaParsleyMarkdownReader
import SagaSwimRenderer
import HTML

func renderPage(context: ItemRenderingContext<EmptyMetadata>) -> Node {
  html(lang: "en-US") {
    body {
      div(id: "content") {
        h1 { context.item.title }
        Node.raw(context.item.body)
      }
    }
  }
}

@main
struct Run {
  static func main() async throws {
    try await Saga(input: "content", output: "deploy")
      // All Markdown files within the `input` folder will be parsed to html.
      .register(
        readers: [.parsleyMarkdownReader()],
        writers: [.itemWriter(swim(renderPage))]
      )

      // Run the step we registered above
      .run()

      // All the remaining files that were not parsed to markdown, so for example 
      // images, raw html files and css, are copied as-is to the output folder.
      .staticFiles()
  }
}
```

> Note: This example uses the [Swim](https://github.com/robb/Swim) library via [SagaSwimRenderer](https://github.com/loopwerk/SagaSwimRenderer) to create type-safe HTML. If you prefer to work with Mustache-type HTML template files, check out [SagaStencilRenderer](https://github.com/loopwerk/SagaStencilRenderer). The <doc:Architecture> document has more information on how Saga works. 


## Custom metadata
Of course Saga can do much more than just render a folder of Markdown files as-is. It can also deal with custom metadata contained within Markdown files - even multiple types of metadata for different kinds of pages.

Let's look at an example Markdown article, `/content/articles/first-article.md`:

```text
---
tags: article, news
summary: This is the summary of the first article
date: 2020-01-01
---
# Hello world
Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.
```

And an example app for a portfolio, `/content/apps/lastfm.md`:

```text
---
url: https://itunes.apple.com/us/app/last-fm-scrobbler/id1188681944?ls=1&mt=8
images: lastfm_1.jpg, lastfm_2.jpg
---
# Last.fm Scrobbler
"Get the official Last.fm Scrobbler App to keep track of what you're listening to on Apple Music. Check out your top artist, album and song charts from all-time to last week, and watch videos of your favourite tracks."
```

As you can see, they both use different metadata: the article has `tags`, a `summary` and a `date`, while the app has a `url` and `images`.

Let's configure Saga to render these files.

```swift
struct ArticleMetadata: Metadata {
  let tags: [String]
  let summary: String?
}

struct AppMetadata: Metadata {
  let url: URL?
  let images: [String]?
}

@main
struct Run {
  static func main() async throws {
    try await Saga(input: "content", output: "deploy")
      // All Markdown files within the "articles" subfolder will be parsed to html,
      // using `ArticleMetadata` as the item's metadata type.
      .register(
        folder: "articles",
        metadata: ArticleMetadata.self,
        readers: [.parsleyMarkdownReader()],
        writers: [
          .itemWriter(swim(renderArticle)),
          .listWriter(swim(renderArticles), paginate: 20),
          .tagWriter(swim(renderTag), tags: \.metadata.tags),
          .yearWriter(swim(renderYear)),

          // Atom feed for all articles, and a feed per tag
          .listWriter(swim(renderFeed), output: "feed.xml"),
          .tagWriter(swim(renderTagFeed), output: "tag/[key]/feed.xml", tags: \.metadata.tags),
        ]
      )

      // All Markdown files within the "apps" subfolder will be parsed to html,
      // using `AppMetadata` as the item's metadata type.
      .register(
        folder: "apps",
        metadata: AppMetadata.self,
        readers: [.parsleyMarkdownReader()],
        writers: [.listWriter(swim(renderApps))]
      )

      // All the remaining Markdown files will be parsed to html,
      // using the default `EmptyMetadata` as the item's metadata type.
      .register(
        readers: [.parsleyMarkdownReader()],
        writers: [.itemWriter(swim(renderItem))]
      )

      // Run the steps we registered above
      .run()

      // All the remaining files that were not parsed to markdown, so for example images,
      // raw html files and css, are copied as-is to the output folder.
      .staticFiles()
  }
}
```

While that might look a bit overwhelming, it should be easy to follow what each `register` step does, each operating on a set of files in a subfolder and processing them in different ways.

Please check out the [Example project](https://github.com/loopwerk/Saga/blob/main/Example) for a more complete picture of Saga. Simply open `Package.swift`, wait for the dependencies to be downloaded, and run the project from within Xcode. Or run from the command line: `swift run`. The example project contains articles with tags and pagination, an app portfolio, static pages, RSS feeds for all articles and per tag, statically typed HTML templates, and more.

You can also check the [source of loopwerk.io](https://github.com/loopwerk/loopwerk.io), which is completely built with Saga.


## Writers
In the custom metadata example above, you can see that the articles step uses four different kinds of writers: `itemWriter`, `listWriter`, `tagWriter`, and `yearWriter`. Each writer takes a renderer function, in this case `swim`, using a locally defined function with the HTML template. The `swim` function comes from the [SagaSwimRenderer](https://github.com/loopwerk/SagaSwimRenderer) library, whereas `renderArticle`, `renderArticles`, `renderTag` and the rest are locally defined in your project. They are the actual HTML templates, using a strongly typed DSL. 

> tip: If you prefer to work with Mustache-type HTML template files, check out [SagaStencilRenderer](https://github.com/loopwerk/SagaStencilRenderer).

The four different writers are all used for different purposes:

- `itemWriter` writes a single item to a single file. For example `content/articles/my-article.md` will be written to `deploy/articles/my-article.html`, or `content/index.md` to `deploy/index.html`.
- `listWriter` writes an array of items to multiple files. For example to create an `deploy/articles/index.html` page that lists all your articles in a paginated manner.
- `tagWriter` writes an array of items to multiple files, based on a tag. If you tag your articles you can use this to render tag pages like `deploy/articles/iOS/index.html`.
- `yearWriter` is similar to `tagWriter` but uses the publication date of the item. You can use this to create year-based archives of your articles, for example `deploy/articles/2022/index.html`.

For more information, please check out ``Writer``.


## Extending Saga
It's very easy to add your own step to Saga where you can access the items and run your own code:

```swift
extension Saga {
  @discardableResult
  func createArticleImages() -> Self {
    let articles = fileStorage.compactMap { $0.item as? Item<ArticleMetadata> }

    for article in articles {
      let destination = (self.outputPath + article.relativeDestination.parent()).string + ".png"
      // generate an image and write it to `destination`
    }

    return self
  }
}

try await Saga(input: "content", output: "deploy")
 // ...register and run steps...
 .createArticleImages()
```

But probably more common and useful is to use the `itemProcessor` parameter of the readers:

```swift
func addExclamationToTitle(item: Item<EmptyMetadata>) async {
  // Do whatever you want with the Item - you can even use async functions and await them!
  item.title.append("!")
}

@main
struct Run {
  static func main() async throws {
    try await Saga(input: "content", output: "deploy")
      .register(
        readers: [.parsleyMarkdownReader(itemProcessor: addExclamationToTitle)],
        writers: [.itemWriter(swim(renderItem))]
      )
  }
}
```

> tip: You can check the [source of loopwerk.io](https://github.com/loopwerk/loopwerk.io), which uses a custom item processors and a custom processing step, for more inspiration.

It's also easy to add your own readers and renderers; search for [saga-plugin](https://github.com/topics/saga-plugin) on Github. For example, [SagaInkMarkdownReader](https://github.com/loopwerk/SagaInkMarkdownReader) adds an `.inkMarkdownReader` that uses Ink and Splash.

## Development server

From your website folder you can run the following command to start a development server, which rebuilds your website on changes, and reloads the browser as well.

```
swift run watch [input-folders, separated by a space] [output-folder]
```

Use the same relative input- and output folders as you gave to Saga. Example: `swift run watch content Sources deploy` to rebuild whenever you change your content or your Swift code.

This functionality does depend on a globally installed [browser-sync](https://browsersync.io), and only works on macOS, not Linux.

```
npm install -g browser-sync
```
