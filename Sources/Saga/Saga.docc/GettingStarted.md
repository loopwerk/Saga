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


## Frontmatter
Markdown files can include a frontmatter block at the top, delimited by `---`. Saga has built-in support for the following frontmatter properties:

- **title**: The title of the item. If not set, Saga uses the first heading in the document, or the filename as a last resort.
- **date**: The publication date, in `yyyy-MM-dd` format. If not set, Saga uses the file's creation date.
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
Saga can deal with custom metadata contained within frontmatter blocks - even multiple types of metadata for different kinds of pages.

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
// Define our custom Metadata
struct ArticleMetadata: Metadata {
  let tags: [String]
  let summary: String?
}

struct AppMetadata: Metadata {
  let url: URL?
  let images: [String]?
}

// Which we then use in our Saga pipeline
try await Saga(input: "content", output: "deploy")
  // All Markdown files within the "articles" subfolder will be parsed to html,
  // using `ArticleMetadata` as the item's metadata type.
  .register(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.parsleyMarkdownReader],
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
    readers: [.parsleyMarkdownReader],
    writers: [.listWriter(swim(renderApps))]
  )

  // All the remaining Markdown files will be parsed to html,
  // using the default `EmptyMetadata` as the item's metadata type.
  .register(
    readers: [.parsleyMarkdownReader],
    writers: [.itemWriter(swim(renderPage))]
  )

  // Run the steps we registered above.
  .run()
```

While that might look a bit overwhelming, it should be easy to follow what each `register` step does, each operating on a set of files in a subfolder and processing them in different ways.

Please check out the [Example project](https://github.com/loopwerk/Saga/blob/main/Example) for a more complete picture of Saga. The example project contains articles with tags and pagination, an app portfolio, static pages, RSS feeds for all articles and per tag, statically typed HTML templates, and more.

You can also check the source code of [loopwerk.io](https://github.com/loopwerk/loopwerk.io) or [getsaga.dev](https://github.com/loopwerk/getsaga.dev), both of which are completely built with Saga.


## Writers
In the custom metadata example above, you can see that the articles step uses four different kinds of writers: `itemWriter`, `listWriter`, `tagWriter`, and `yearWriter`. Each writer takes a render function responsible for turning an item (or an array of items) into an HTML string.

The four different writers are all used for different purposes:

- `itemWriter` writes a single item to a single file. For example `content/articles/my-article.md` will be written to `deploy/articles/my-article/index.html`, or `content/index.md` to `deploy/index.html`.
- `listWriter` writes an array of items to one or multiple files (depending on pagination). For example to create an `deploy/articles/index.html` page that lists all your articles.
- `tagWriter` writes an array of items to multiple files, based on a tag. If you tag your articles you can use this to render tag pages like `deploy/articles/iOS/index.html`.
- `yearWriter` is similar to `tagWriter` but uses the publication date of the item. You can use this to create year-based archives of your articles, for example `deploy/articles/2022/index.html`.

For more information, please check out ``Writer``.


## Development server
From your website folder you can run the following command to start a development server, which rebuilds your website on changes, and reloads the browser as well.

```shell-session
$ saga dev
```

Saga automatically watches your content folder and `Sources/` for changes. Content changes trigger an in-process rebuild; Swift source changes trigger a recompilation. The dev server runs on port 3000 by default:

```shell-session
$ saga dev --port 8080
```

To prevent certain files from triggering rebuilds (e.g. generated CSS), use ``Saga/ignoreChanges(_:)`` in your Swift code:

```swift
try await Saga(input: "content", output: "deploy")
  .ignoreChanges("output.css")
  .register(/* ... */)
  .run()
```

To just build the site without starting a server:

```shell-session
$ saga build
```

See <doc:Installation> for how to install the `saga` CLI.
