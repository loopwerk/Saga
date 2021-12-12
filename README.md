<p align="center">
  <img src="logo.png" width="200" alt="tag-changelog" />
</p>

A static site generator, written in Swift, allowing you to supply your own metadata types for your items. Saga uses a system of extendible readers, renderers, and writers, supporting things like Atom feeds, paginating, and strongly typed HTML templates.

Saga uses async/await and as such requires at least Swift 5.5, and runs on both Mac (macOS 12) and Linux. Version 0.22.0 can be used on macOS 11 with Swift 5.2.


## Usage
Saga is quite flexible: for example you can have one set of metadata for the articles on your blog, and another set of metadata for the apps in your portfolio. At the same time it's quite easy to configure.

Let's start with the most basic example: rendering all Markdown files to HTML.

```swift
import Saga
import SagaParsleyMarkdownReader
import SagaSwimRenderer
import HTML

func renderPage(context: ItemRenderingContext<EmptyMetadata, EmptyMetadata>) -> Node {
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
    try await Saga(input: "content", output: "deploy", siteMetadata: EmptyMetadata())
      // All files will be parsed to html.
      .register(
        metadata: EmptyMetadata.self,
        readers: [.parsleyMarkdownReader()],
        writers: [
          .itemWriter(swim(renderPage))
        ]
      )

      // Run the step we registered above
      .run()

      // All the remaining files that were not parsed to markdown, so for example images, raw html files and css,
      // are copied as-is to the output folder.
      .staticFiles()
  }
}
```

That example uses the [Swim](https://github.com/robb/Swim) library to create type-safe HTML.

Of course Saga can do much more than just render a folder of Markdown files as-is. It can also deal with custom metadata contained within Markdown files - even multiple types of metadata for different kinds of pages.

Let's look at an example Markdown article, `/content/articles/first-article.md`:

``` markdown
---
tags: article, news
summary: This is the summary of the first article
date: 2020-01-01
---
# Hello world
Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.
```

And an example app for a portfolio, `/content/apps/lastfm.md`:

``` markdown
---
url: https://itunes.apple.com/us/app/last-fm-scrobbler/id1188681944?ls=1&mt=8)
images: lastfm_1.jpg, lastfm_2.jpg
---
# Last.fm Scrobbler
"Get the official Last.fm Scrobbler App to keep track of what you're listening to on Apple Music. Check out your top artist, album and song charts from all-time to last week, and watch videos of your favourite tracks."
```

As you can see, they both use different metadata: the article has `tags`, a `summary` and a `date`, while the app has a `url` and `images`.

Let's configure Saga to render these files, while also adding a `SiteMetadata` type that will be given to each template.

``` swift
import Foundation
import Saga
import SagaParsleyMarkdownReader
import SagaSwimRenderer

struct ArticleMetadata: Metadata {
  let tags: [String]
  let summary: String?
}

struct AppMetadata: Metadata {
  let url: URL?
  let images: [String]?
}

// SiteMetadata is given to every RenderingContext.
// You can put whatever properties you want in here.
struct SiteMetadata: Metadata {
  let url: URL
  let name: String
}

let siteMetadata = SiteMetadata(
  url: URL(string: "http://www.example.com")!,
  name: "Example website"
)

@main
struct Run {
  static func main() async throws {
    try await Saga(input: "content", output: "deploy", siteMetadata: siteMetadata)
      // All markdown files within the "articles" subfolder will be parsed to html,
      // using ArticleMetadata as the Item's metadata type.
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

      // All markdown files within the "apps" subfolder will be parsed to html,
      // using AppMetadata as the Item's metadata type.
      .register(
        folder: "apps",
        metadata: AppMetadata.self,
        readers: [.parsleyMarkdownReader()],
        writers: [.listWriter(swim(renderApps))]
      )
     
      // All the remaining markdown files will be parsed to html,
      // using the default EmptyMetadata as the Item's metadata type.
      .register(
        metadata: EmptyMetadata.self,
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


## Extending Saga
It's very easy to add your own step to Saga where you can access the items and run your own code:

``` swift
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

``` swift
func itemProcessor(item: Item<EmptyMetadata>) async {
  // Do whatever you want with the Item - you can even use async functions and await them!
  item.title.append("!")
}

@main
struct Run {
  static func main() async throws {
    try await Saga(input: "content", output: "deploy")
      .register(
        metadata: EmptyMetadata.self,
        readers: [.parsleyMarkdownReader(itemProcessor: itemProcessor)],
        writers: [.itemWriter(swim(renderItem))]
      )
  }
}
```

It's also easy to add your own readers, writers, and renderers; search for [saga-plugin](https://github.com/topics/saga-plugin) on Github. For example, [SagaInkMarkdownReader](https://github.com/loopwerk/SagaInkMarkdownReader) adds an `.inkMarkdownReader` that uses Ink and Splash.


## Getting started
Create a new folder and inside of it run `swift package init --type executable`, and then `open Package.swift`. Edit Package.swift to add the Saga dependency, plus a reader and optionally a renderer (see Architecture below), so that it looks something like this:

``` swift
// swift-tools-version:5.5

import PackageDescription

let package = Package(
  name: "MyWebsite",
  platforms: [
    .macOS(.v12)
  ],
  dependencies: [
    .package(url: "https://github.com/loopwerk/Saga", from: "1.0.0"),
    .package(url: "https://github.com/loopwerk/SagaParsleyMarkdownReader", from: "0.5.0"),
    .package(url: "https://github.com/loopwerk/SagaSwimRenderer", from: "0.6.0"),
  ],
  targets: [
    .executableTarget(
      name: "MyWebsite",
      dependencies: [
        "Saga", 
        "SagaParsleyMarkdownReader", 
        "SagaSwimRenderer"
      ]
    )
  ]
)
```

Now you can `import Saga` and use it.

### Development server
From your website folder you can run the following command to start a development server, which rebuilds your website on changes, and reloads the browser as well.

```
swift run watch [input-folders, separated by a space] [output-folder]
```

Use the same relative input- and output folders as you gave to Saga. Example: `swift run watch content Sources deploy` to rebuild whenever you change your content or your Swift code.

This functionality does depend on a globally installed [browser-sync](https://browsersync.io), and only works on macOS, not Linux.

```
npm install -g browser-sync
```


## Architecture
Saga does its work in multiple stages.

1. First, it finds all the files within the `input` folder
2. Then, for every registered step, it passes those files to matching readers (matching based on the extensions the reader declares it supports). Readers are responsible for turning for example Markdown or RestructuredText files, into `Item` instances. Such readers are not bundled with Saga itself, instead you'll have to install one such as [SagaParsleyMarkdownReader](https://github.com/loopwerk/SagaParsleyMarkdownReader), [SagaPythonMarkdownReader](https://github.com/loopwerk/SagaPythonMarkdownReader), or [SagaInkMarkdownReader](https://github.com/loopwerk/SagaInkMarkdownReader).
3. Finally Saga runs all the registered steps again, now executing the writers. These writers expect to be given a function that can turn a `RenderingContext` (which holds the `Item` among other things) into a `String`, which it'll then write to disk, to the `output` folder. To turn an `Item` into a HTML `String`, you'll want to use a template language or a HTML DSL, such as [SagaSwimRenderer](https://github.com/loopwerk/SagaSwimRenderer) or [SagaStencilRenderer](https://github.com/loopwerk/SagaStencilRenderer).

Readers are expected to support the parsing of metadata contained within a document, such as this example for Markdown files:

```
---
tags: article, news
summary: This is the summary
---
# Hello world
Hello there.
```

The three officially supported Markdown readers all do support the parsing of metadata.

The official recommendation is to use [SagaParsleyMarkdownReader](https://github.com/loopwerk/SagaParsleyMarkdownReader) for reading Markdown files and [SagaSwimRenderer](https://github.com/loopwerk/SagaSwimRenderer) to render them using [Swim](https://github.com/robb/Swim), which offers a great HTML DSL using Swift's function builders. 


## Thanks
Inspiration for the API of Saga is very much owed to my favorite (but sadly long unmaintained) static site generator: [liquidluck](https://github.com/avelino/liquidluck). Its system of multiple readers and writers is really good and I wanted something similar.

Thanks also goes to [Publish](https://github.com/JohnSundell/Publish), another static site generator written in Swift, for inspiring me towards custom strongly typed metadata. A huge thanks also for its metadata decoder, which was copied over shamelessly.

You can read [this series of articles](https://www.loopwerk.io/articles/tag/saga/) discussing the inspiration behind the API.


## Websites using Saga
- https://loopwerk.io ([source](https://github.com/loopwerk/loopwerk.io))
- https://david.dev
