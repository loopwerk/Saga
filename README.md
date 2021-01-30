# Saga

A static site generator, written in Swift, allowing you to supply your own metadata type for your pages. It's quite flexible: for example you can have one set of metadata for the articles on your blog, and another set of metadata for the apps in your portfolio. At the same time it's quite easy to configure:

``` swift
struct ArticleMetadata: Metadata {
  let tags: [String]
}

struct AppMetadata: Metadata {
  let url: URL?
  let images: [String]?
}

// Add some helper methods to the Page type that Saga provides
extension Page {
  var isArticle: Bool {
    return metadata is ArticleMetadata
  }
  var isPublicArticle: Bool {
    return (metadata as? ArticleMetadata)?.isPublic ?? false
  }
  var isApp: Bool {
    return metadata is AppMetadata
  }
  var tags: [String] {
    return (metadata as? ArticleMetadata)?.tags ?? []
  }
}

try Saga(input: "content", output: "deploy")
  // All markdown files within the "articles" subfolder will be parsed to html,
  // using ArticleMetadata as the Page's metadata type.
  .read(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.markdownReader()]
  )
  // All markdown files within the "apps" subfolder will be parsed to html,
  // using AppMetadata as the Page's metadata type.
  .read(
    folder: "apps",
    metadata: AppMetadata.self,
    readers: [.markdownReader()]
  )
  // All the remaining markdown files will be parsed to html,
  // using the default EmptyMetadata as the Page's metadata type.
  .read(
    metadata: EmptyMetadata.self,
    readers: [.markdownReader()]
  )
  // Now that we have read all the markdown pages, we're going to write
  // them all to disk using a variety of writers.
  .write(
    templates: "templates",
    writers: [
      // Articles
      .section(prefix: "articles", filter: { $0.isPublicArticle }, writers: [
        .pageWriter(template: "article.html"),
        .listWriter(template: "articles.html"),
        .tagWriter(template: "tag.html", tags: { $0.tags }),
        .yearWriter(template: "year.html"),
      ]),
      
      // Apps
      .listWriter(template: "apps.html", output: "apps/index.html", filter: { $0.isApp }),

      // Other pages
      .pageWriter(template: "page.html", filter: { $0.metadata is EmptyMetadata }),
    ]
  )
  // All the remaining files that were not parsed to markdown, so for example images,
  // raw html files and css, are copied as-is to the output folder.
  .staticFiles()
```

At the moment the template library [Stencil](https://github.com/stencilproject/Stencil) is used, but I may replace it with (or add next to it) a statically typed version such as https://github.com/JohnSundell/Plot or https://github.com/pointfreeco/swift-html.

``` html
{% extends "base.html" %}

{% block title %}Articles{% endblock %}

{% block content %}
  <h1>Articles</h1>
  {% for page in pages %}
    <a href="{{ page | url }}">{{ page.title }}</a><br/>
    {{ page.summary }}
  {% endfor %}
{% endblock %}
```

Please check out the Example folder. Simply open `Package.swift`, wait for the dependencies to be downloaded, and run the project from within Xcode. Or run from the command line: `swift run`.

Your Markdown files can be extended with metadata using the YAML front matter style:

```
---
tags: article, news
summary: This is the summary
---
# Hello world
Hello there.
```

## Extending Saga

It's very easy to add your own step to Saga where you can modify the pages however you wish.

``` swift
extension Saga {
  func modifyPages() -> Self {
    let pages = fileStorage.compactMap(\.page)
    for page in pages {
      page.title.append("!")
    }

    return self
  }
}

try Saga(input: "content", output: "deploy")
  .read(
    metadata: EmptyMetadata.self,
    readers: [.markdownReader()]
  )
  .modifyPages()
  .write(
    templates: "templates",
    writers: [
      // ...
    ]
  )
```

You can also use `markdownReader`'s `pageProcessor` parameter.

``` swift
func pageProcessor(page: Page) {
  // Do whatever you want with the Page
  page.title.append("!")
}

try Saga(input: "content", output: "deploy")
  .read(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.markdownReader(pageProcessor: pageProcessor)]
  )
```

## Getting started

Create a new folder and inside of it run `swift package init --type executable`, and then `open Package.swift`. Edit Package.swift to add the Saga dependency, so that it looks something like this:

``` swift
// swift-tools-version:5.3

import PackageDescription

let package = Package(
  name: "MyWebsite",
  dependencies: [
    .package(name: "Saga", url: "https://github.com/loopwerk/Saga.git", from: "0.2.0"),
  ],
  targets: [
    .target(
      name: "MyWebsite",
      dependencies: ["Saga"]),
    .testTarget(
      name: "MyWebsiteTests",
      dependencies: ["MyWebsite"]),
  ]
)
```

Now, inside of `Sources/MyWebsite/main.swift` you can `import Saga` and use it. The input, output and template folders are relative to the root folder where Package.swift is located.


## TODO

- Remove the page title from the page body - right now it's not possible to add content between the title and the body of an article, something that I do need for my own website.
- Add paginating support for list/tag/year writers.
- Replace the Ink and Splash dependencies (see known limitations, below).
- Research a way to auto-run on changes, maybe even reloading the browser as well.
- Docs and tests.

## Known limitations

- Stencil, the template language, doesn't support rendering computed properties (https://github.com/stencilproject/Stencil/issues/219). So if you extend `Page` with computed properties, you sadly won't be able to render them in your templates.
- Stencil's template inheritance doesn't support overriding blocks through multiple levels (https://github.com/stencilproject/Stencil/issues/275)
- Ink, the Markdown parser, is buggy and is missing features (https://github.com/JohnSundell/Ink/pull/49, https://github.com/JohnSundell/Ink/pull/63). Pull requests don't seem to get merged anymore?
- Splash, the syntax highlighter, only has support for Swift grammar. If you write articles with, let's say, JavaScript code blocks, they won't get properly highlighted.

## Thanks

Inspiration for the API of Saga is very much owed to my favorite (but sadly long unmaintained) static site generator: [liquidluck](https://github.com/avelino/liquidluck). Its system of multiple readers and writers is really good and I wanted something similar.

Thanks also goes to [Publish](https://github.com/JohnSundell/Publish), another static site generator written in Swift, for inspiring me towards custom strongly typed metadata. A huge thanks also for its metadata decoder code, which was copied over shamelessly.

## FAQ

Q: Is this ready for production?  
A: No. This is in very early stages of development, mostly as an exercise. I have no clue if and when I'll finish it or to what degree. I still use [liquidluck](https://github.com/avelino/liquidluck) for my own static sites, which should tell you enough.