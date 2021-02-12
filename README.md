# Saga
A static site generator, written in Swift, allowing you to supply your own metadata type for your pages. Read [this series of articles](https://www.loopwerk.io/articles/tag/saga/) discussing the inspiration behind the API, the current state of the project and future plans.


## Usage
Saga is quite flexible: for example you can have one set of metadata for the articles on your blog, and another set of metadata for the apps in your portfolio. At the same time it's quite easy to configure:

``` swift
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
// You can put whatever you want in here, as long as it confirms to the Metadata protocol.
// If you have no need for custom site metadata, just pass EmptyMetadata() to Saga, below.
struct SiteMetadata: Metadata {
  let url: URL
  let name: String
}

let siteMetadata = SiteMetadata(
  url: URL(string: "http://www.example.com")!,
  name: "Example website"
)

try Saga(input: "content", output: "deploy", templates: "templates", siteMetadata: siteMetadata)
  // All markdown files within the "articles" subfolder will be parsed to html,
  // using ArticleMetadata as the Page's metadata type.
  .register(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.parsleyMarkdownReader()],
    writers: [
      .pageWriter(swim(renderArticle)),
      .listWriter(swim(renderArticles)),
      .tagWriter(swim(renderTag), tags: \.metadata.tags),
      .yearWriter(swim(renderYear)),
    ]
  )
  // All markdown files within the "apps" subfolder will be parsed to html,
  // using AppMetadata as the Page's metadata type.
  .register(
    folder: "apps",
    metadata: AppMetadata.self,
    readers: [.parsleyMarkdownReader()],
    writers: [.listWriter(swim(renderApps))]
  )
  // All the remaining markdown files will be parsed to html,
  // using the default EmptyMetadata as the Page's metadata type.
  .register(
    metadata: EmptyMetadata.self,
    readers: [.parsleyMarkdownReader()],
    writers: [.pageWriter(swim(renderPage))]
  )
  // Run the steps we registered above
  .run()
  // All the remaining files that were not parsed to markdown, so for example images,
  // raw html files and css, are copied as-is to the output folder.
  .staticFiles()
```

For more examples please check out the [Example folder](https://github.com/loopwerk/Saga/blob/main/Example/Sources/Example/main.swift). Simply open `Package.swift`, wait for the dependencies to be downloaded, and run the project from within Xcode. Or run from the command line: `swift run`.

You can also check the [source of loopwerk.io](https://github.com/loopwerk/loopwerk.io), which is completely built with Saga.

## Extending Saga
It's very easy to add your own step to Saga where you can access the pages and run your own code:

``` swift
extension Saga {
  @discardableResult
  func createArticleImages() -> Self {
    let articles = fileStorage.compactMap { $0.page as? Page<ArticleMetadata> }

    for article in articles {
      let destination = (self.outputPath + article.relativeDestination.parent()).string + ".png"
      _ = try? shellOut(to: "python image.py", arguments: ["\"\(article.title)\"", destination], at: (self.rootPath + "ImageGenerator").string)
    }

    return self
  }
}

try Saga(input: "content", output: "deploy")
 // ...register and run steps...
 .createArticleImages()
```

But probably more common and useful is to use the `pageProcessor` parameter of the readers:

``` swift
func pageProcessor(page: Page<EmptyMetadata>) {
  // Do whatever you want with the Page
  page.title.append("!")
}

try Saga(input: "content", output: "deploy")
  .register(
    metadata: EmptyMetadata.self,
    readers: [.parsleyMarkdownReader(pageProcessor: pageProcessor)],
    writers: [.pageWriter(swim(renderPage))]
  )
```

It's also easy to add your own readers, writers, and renderers; search for [saga-plugin](https://github.com/topics/saga-plugin) on Github. For example, [SagaInkMarkdownReader](https://github.com/loopwerk/SagaInkMarkdownReader) adds an `.inkMarkdownReader` that uses Ink and Splash.

## Getting started
Create a new folder and inside of it run `swift package init --type executable`, and then `open Package.swift`. Edit Package.swift to add the Saga dependency, plus a reader and optionally a renderer (see Architecture below), so that it looks something like this:

``` swift
// swift-tools-version:5.2

import PackageDescription

let package = Package(
  name: "MyWebsite",
  platforms: [
    .macOS(.v10_15)
  ],
  dependencies: [
    .package(name: "Saga", url: "https://github.com/loopwerk/Saga.git", from: "0.14.0"),
    .package(url: "https://github.com/loopwerk/SagaParsleyMarkdownReader", from: "0.2.0"),
    .package(url: "https://github.com/loopwerk/SagaSwimRenderer", from: "0.1.0"),
  ],
  targets: [
    .target(
      name: "MyWebsite",
      dependencies: [
        "Saga", 
        "SagaParsleyMarkdownReader", 
        "SagaSwimRenderer"
      ]
    ),
    .testTarget(
      name: "MyWebsiteTests",
      dependencies: ["MyWebsite"]),
  ]
)
```

Now, inside of `Sources/MyWebsite/main.swift` you can `import Saga` and use it.

### Development server
From your website folder you can run the following command to start a development server, which rebuilds your website on changes, and reloads the browser as well.

```
swift run watch [input-folder] [output-folder]
```

Use the same relative input- and output folders as you gave to Saga.

This functionality does depend on a globally installed [lite-server](https://github.com/johnpapa/lite-server).

```
npm install --global lite-server
```


## Architecture
Saga does its work in multiple stages.

1. First, it finds all the files within the `input` folder
2. Then, for every registered step, it passes those files to matching readers (matching based on the extensions the reader declares it supports). Readers are responsible for turning for example Markdown or RestructuredText files, into `Page` instances. Such readers are not bundled with Saga itself, instead you'll have to install one such as [SagaParsleyMarkdownReader](https://github.com/loopwerk/SagaParsleyMarkdownReader), [SagaPythonMarkdownReader](https://github.com/loopwerk/SagaPythonMarkdownReader), or [SagaInkMarkdownReader](https://github.com/loopwerk/SagaInkMarkdownReader).
3. Finally Saga runs all the registered steps again, now executing the writers. These writers expect to be given a function that can turn a `RenderingContext` (which hold the `Page` among other things) into a `String`, which it'll then write to disk, to the `output` folder. To turn a `Page` into a HTML `String`, you'll want to use a template language or a HTML DSL, such as [SagaSwimRenderer](https://github.com/loopwerk/SagaSwimRenderer).

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


## TODO
- Add paginating support for list/tag/year writers.
- Docs and tests.


## Thanks
Inspiration for the API of Saga is very much owed to my favorite (but sadly long unmaintained) static site generator: [liquidluck](https://github.com/avelino/liquidluck). Its system of multiple readers and writers is really good and I wanted something similar.

Thanks also goes to [Publish](https://github.com/JohnSundell/Publish), another static site generator written in Swift, for inspiring me towards custom strongly typed metadata. A huge thanks also for its metadata decoder, which was copied over shamelessly.


## Websites using Saga
- https://github.com/loopwerk/loopwerk.io
