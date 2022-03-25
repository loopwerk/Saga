<p align="center">
  <img src="logo.png" width="200" alt="tag-changelog" />
</p>

A static site generator, written in Swift, allowing you to supply your own metadata types for your items. Saga uses a system of extendible readers, renderers, and writers, supporting things like Atom feeds, paginating, and strongly typed HTML templates.

Saga is quite flexible: for example you can have one set of metadata for the articles on your blog, and another set of metadata for the apps in your portfolio. At the same time it's quite easy to configure.

> Saga uses async/await and as such requires at least Swift 5.5, and runs on both Mac (macOS 12) and Linux. Version 0.22.0 can be used on macOS 11 with Swift 5.2.


## Syntax

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


## Documentation
Please refer to the documentation for installation instructions, system requirements, basic getting started information and tutorials, and how-to's for more advanced things.


## Websites using Saga
- https://loopwerk.io ([source](https://github.com/loopwerk/loopwerk.io))
- https://david.dev
