# Getting Started with Saga

An overview of how to configure Saga to render your pages and articles.


## Overview
Let's start with the most basic example: rendering all Markdown files to HTML. This code goes in your project's `main.swift` file.

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

try await Saga(input: "content", output: "deploy")
  // All Markdown files within the `input` folder will be parsed to html.
  .register(
    readers: [.parsleyMarkdownReader],
    writers: [.itemWriter(swim(renderPage))]
  )

  // Run the step we registered above.
  // Static files (images, css, etc.) are copied automatically.
  .run()
```

> Note: This example uses the [Swim](https://github.com/robb/Swim) library via [SagaSwimRenderer](https://github.com/loopwerk/SagaSwimRenderer) to create type-safe HTML, but more template languages are supported. Check [GetSaga.dev](https://getsaga.dev) for a complete list of available plugins, or browse the [saga-plugin](https://github.com/topics/saga-plugin) tag on GitHub. The <doc:Architecture> document has more information on how Saga works.


## Development server
From your website folder you can run the following command to start a development server, which rebuilds your website on changes, and reloads the browser as well. (See <doc:Installation> for how to install the `saga` CLI.)

```shell-session
$ saga dev
```

Saga automatically watches your content folder and `Sources/` for changes. Content changes trigger an in-process rebuild; Swift source changes trigger a recompilation. The dev server runs on port 3000 by default, but you can choose a different port:

```shell-session
$ saga dev --port 8080
```

To just build the site without starting a server:

```shell-session
$ saga build
```


## Markdown files
A typical Markdown file starts with a level 1 heading, which Saga uses as the item's title. The title is then split off from the rest of the body and exposed as `item.title`, so your template can render it separately.

```text
# About this site
Content goes here.
```


## Frontmatter
Markdown files can optionally include a frontmatter block at the top, delimited by `---`. Saga has built-in support for the following frontmatter properties:

- **title**: Overrides the title that would otherwise be taken from the first level 1 heading. Pick one or the other; if both are present, the first level 1 heading is still stripped from the body. If neither is present, the filename is used as the title.
- **date**: The publication date, such as `2026-10-22`, `2026-10-22 12:07` or `2026-10-22T12:07:31+02:00`. Without a time zone, the local time zone is used. If not set, Saga uses the file's creation date.
- **slug**: Overrides the output path. For example, setting `slug: my-page` writes the item to `my-page/index.html` instead of deriving the path from the filename.

```text
---
title: About this site
date: 2024-06-15
slug: about
---
Content goes here.
```

Any other frontmatter properties can be parsed using strongly typed metadata (see below).


## Custom metadata
Articles usually need more than a title and a body, like tags and a summary. You add these to the frontmatter, and describe them in Swift with a type that conforms to ``Metadata``.

Here's an article, `content/articles/hello-world.md`:

```text
---
tags: swift, saga
summary: The very first article on my new website.
date: 2026-01-12
---
# Hello, world
Welcome to my new website!
```

Its metadata type has a property for each custom frontmatter field. Comma-separated values like the tags are decoded into an array. Saga handles `title`, `date` and `slug` itself, so those don't belong in your metadata type.

```swift
struct ArticleMetadata: Metadata {
  let tags: [String]
  let summary: String?
}
```

Articles can leave out optional properties like `summary`. When a file is missing a required property, Saga logs a warning and skips the file.

Now register a step for the `articles` folder that uses this metadata type:

```swift
try await Saga(input: "content", output: "deploy")
  // All Markdown files within the "articles" subfolder will be parsed to html,
  // using `ArticleMetadata` as the item's metadata type.
  .register(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.parsleyMarkdownReader],
    writers: [
      .itemWriter(swim(renderArticle)),
      .listWriter(swim(renderArticles)),
    ]
  )

  // All the remaining Markdown files will be parsed to html,
  // using the default `EmptyMetadata` as the item's metadata type.
  .register(
    readers: [.parsleyMarkdownReader],
    writers: [.itemWriter(swim(renderPage))]
  )

  .run()
```

The item writer writes a page for every article, and the list writer writes a single page that lists all of them, at `articles/index.html`.

> Important: Steps run in the order you register them, and each step claims the files it reads, so later steps don't see them. That's why the step without a folder comes last: it handles all the remaining Markdown files. If it came first, it would render your articles as plain pages.

The templates have typed access to the metadata. `renderArticle` receives an ``ItemRenderingContext`` with a single article, and `renderArticles` an ``ItemsRenderingContext`` with all articles, newest first:

```swift
func renderArticle(context: ItemRenderingContext<ArticleMetadata>) -> Node {
  html(lang: "en-US") {
    body {
      article {
        h1 { context.item.title }
        p { "Tagged: \(context.item.metadata.tags.joined(separator: ", "))" }
        Node.raw(context.item.body)
      }
    }
  }
}

func renderArticles(context: ItemsRenderingContext<ArticleMetadata>) -> Node {
  html(lang: "en-US") {
    body {
      h1 { "Articles" }
      context.items.map { article in
        div {
          h2 {
            a(href: article.url) { article.title }
          }
          if let summary = article.metadata.summary {
            p { summary }
          }
        }
      }
    }
  }
}
```

Swim's builders don't support `for` loops, so use `map` to turn each article into HTML.

> Tip: These templates repeat the same HTML shell. See <doc:ReusableHTMLLayouts> to move it into a shared base layout.

Every step can have its own metadata type. A portfolio in `content/apps`, for example, could use an `AppMetadata` type with a `url` and `images`, while your articles keep using `ArticleMetadata`.


## Writers
The articles step above uses two kinds of writers, but Saga has four. Each writer takes a render function responsible for turning an item (or an array of items) into a string.

- `itemWriter` writes a single item to a single file. For example `content/articles/my-article.md` will be written to `deploy/articles/my-article/index.html`, or `content/index.md` to `deploy/index.html`.
- `listWriter` writes an array of items to one or multiple files (depending on pagination). For example to create an `deploy/articles/index.html` page that lists all your articles.
- `tagWriter` writes an array of items to multiple files, based on a tag. If you tag your articles you can use this to render tag pages like `deploy/articles/tag/swift/index.html`.
- `yearWriter` is similar to `tagWriter` but uses the publication date of the item. You can use this to create year-based archives of your articles, for example `deploy/articles/2022/index.html`.

For example, this adds tag pages, year archives, and an Atom feed to the articles step:

```swift
.register(
  folder: "articles",
  metadata: ArticleMetadata.self,
  readers: [.parsleyMarkdownReader],
  writers: [
    .itemWriter(swim(renderArticle)),
    .listWriter(swim(renderArticles)),
    .tagWriter(swim(renderTag), tags: \.metadata.tags),
    .yearWriter(swim(renderYear)),
    .listWriter(
      Saga.atomFeed(
        title: "My Website - Articles",
        author: "Your Name",
        baseURL: URL(string: "https://www.example.com")!,
        summary: \.metadata.summary
      ),
      output: "feed.xml"
    ),
  ]
)
```

The tag and year templates receive a ``PartitionedRenderingContext``, whose `key` is the tag or the year. Output paths are relative to the step's folder, so the feed is written to `articles/feed.xml`. See <doc:CustomFeedFormats> for other feed formats.

For more information, please check out ``Writer``.


## Next steps
- <doc:ReusableHTMLLayouts>: share one HTML shell between all your templates.
- <doc:AdvancedUsage>: change items with item processors, create pages that don't come from a Markdown file (like a 404 page), and run code before or after each build.
- <doc:GeneratingSitemaps>: tell search engines about your pages.
- <doc:TailwindCSS>: compile Tailwind CSS as part of your build.

Please check out the [Example project](https://github.com/loopwerk/Saga/blob/main/Example) for a more complete picture of Saga. The example project contains articles with tags and pagination, an app portfolio, static pages, RSS feeds for all articles and per tag, statically typed HTML templates, and more.

You can also check the source code of [loopwerk.io](https://github.com/loopwerk/loopwerk.io) or [getsaga.dev](https://github.com/loopwerk/getsaga.dev), both of which are completely built with Saga.
