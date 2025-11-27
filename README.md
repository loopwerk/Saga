<p align="center">
  <img src="logo.png" width="200" alt="tag-changelog" />
</p>

A static site generator, written in Swift, allowing you to supply your own metadata types for your items. Saga uses a system of extendible readers, renderers, and writers, supporting things like Atom feeds, paginating, and strongly typed HTML templates.

## Flexible metadata
Saga’s main goal is flexibility; specifically the ability to have multiple sets of items, each with their own (strongly typed) metadata. This is something that most other generators do not support. For example you could have a website where you have blog articles under `/blog/`, where each article has one or more tags. You’d have a page for each tag (`/blog/[tag]/`), and you also want an archive per year (`/blog/[year]/`). And of course it all has to be paginated, showing 20 articles per page. You want an RSS feed of all your articles, and a feed per tag. So far, this is nothing special, basically any static site generator can do this.

But what if you also want to add a project portfolio to your site? Where each project has its own markdown file with different metadata than your articles, like a link to the App Store and a set of screenshots. You want to show this on `/portfolio/`, and maybe you also want to create separate pages for your iOS, Android, and web projects. Or let’s say you want to show movie reviews on your site: you store the reviews in separate markdown files, one file per review. Reviews have different metadata yet again, like the year of release, main actors, genre, a rating, a main image. You want to show these reviews on `/movies/`, you want a page per year, per genre, and per actor. Or what about recipes, where you store the cuisine, type of course, and complexity, as metadata? 

There are very few static site generator capable of handling diverse content like this, especially when you’re dealing with multiple types of content within one website. Saga does offer all this flexibility, and then some.

## Code over configuration
Because Saga focuses on code over configuration, there’s no hidden behavior to deal with, no default values you have to overwrite, no magic convention you have to learn, no documentation for hundreds of config options to understand. Everything is strongly typed, from top to bottom, and you tell Saga exactly how to build your site.

## Syntax

```swift
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
      // All files will be parsed to html.
      .register(
        readers: [.parsleyMarkdownReader()],
        writers: [.itemWriter(swim(renderPage))]
      )

      // Run the step we registered above
      .run()

      // All the remaining files that were not parsed from markdown, so for example images, raw html files and css,
      // are copied as-is to the output folder.
      .staticFiles()
  }
}
```

That example uses [Swim](https://github.com/robb/Swim) to create type-safe HTML.

Of course Saga can do much more than just render a folder of markdown files as-is. It can also deal with custom metadata contained within markdown files - even multiple types of metadata for different kinds of pages.


## Documentation
Please refer to the documentation for [installation instructions](https://loopwerk.github.io/Saga/documentation/saga/installation), system requirements, basic [getting started](https://loopwerk.github.io/Saga/documentation/saga/gettingstarted) information, and how-to guides for more advanced things.

The documentation is available from within Xcode (Product > Build Documentation) or at [loopwerk.github.io/Saga/documentation/saga/](https://loopwerk.github.io/Saga/documentation/saga/).


## Plugins
You’ll need to use a markdown reader to parse markdown files to HTML, and you’ll need to use a renderer which offers support for an HTML template. Saga offers multiple options:

- [SagaParsleyMarkdownReader](https://github.com/loopwerk/SagaParsleyMarkdownReader) - a markdown reader for Saga that uses [Parsley](https://github.com/loopwerk/Parsley).
- [SagaInkMarkdownReader](https://github.com/loopwerk/SagaInkMarkdownReader) - a markdown reader for Saga that uses [Ink](https://github.com/JohnSundell/Ink) and [Splash](https://github.com/JohnSundell/Splash).
- [SagaPythonMarkdownReader](https://github.com/loopwerk/SagaPythonMarkdownReader) - a markdown reader for Saga that uses [Python-Markdown](https://github.com/Python-Markdown/markdown) and [Pygments](https://pygments.org).
- [SagaSwimRenderer](https://github.com/loopwerk/SagaSwimRenderer) - use [Swim](https://github.com/robb/Swim) for type-safe HTML.
- [SagaStencilRenderer](https://github.com/loopwerk/SagaStencilRenderer) - use the [Stencil](https://github.com/stencilproject/Stencil) template language.


## Websites using Saga
- https://loopwerk.io ([source](https://github.com/loopwerk/loopwerk.io))
- https://mhoush.com ([source](https://github.com/m-housh/mhoush.com))
- https://www.spamusement.cc/ ([source](https://github.com/kevinrenskers/spamusement.cc))

Is your website built with Saga? Send a pull request to add it to this list!
