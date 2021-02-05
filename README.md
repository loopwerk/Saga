# Saga

A static site generator, written in Swift, allowing you to supply your own metadata type for your pages. Read [this series of articles](https://www.loopwerk.io/articles/tag/saga/) discussing the inspiration behind the API, the current state of the project and future plans.

Saga is quite flexible: for example you can have one set of metadata for the articles on your blog, and another set of metadata for the apps in your portfolio. At the same time it's quite easy to configure:

``` swift
struct ArticleMetadata: Metadata {
  let tags: [String]
  let summary: String?
}

struct AppMetadata: Metadata {
  let url: URL?
  let images: [String]?
}

try Saga(input: "content", output: "deploy", templates: "templates")
  // All markdown files within the "articles" subfolder will be parsed to html,
  // using ArticleMetadata as the Page's metadata type.
  // Furthermore we are only interested in public articles.
  .register(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.markdownReader()],
    writers: [
      .pageWriter(template: "article.html"),
      .listWriter(template: "articles.html"),
      .tagWriter(template: "tag.html", tags: \.metadata.tags),
      .yearWriter(template: "year.html"),
    ]
  )
  // All markdown files within the "apps" subfolder will be parsed to html,
  // using AppMetadata as the Page's metadata type.
  .register(
    folder: "apps",
    metadata: AppMetadata.self,
    readers: [.markdownReader()],
    writers: [.listWriter(template: "apps.html")]
  )
  // All the remaining markdown files will be parsed to html,
  // using the default EmptyMetadata as the Page's metadata type.
  .register(
    metadata: EmptyMetadata.self,
    readers: [.markdownReader()],
    writers: [.pageWriter(template: "page.html")]
  )
  // Run the steps we registered above
  .run()
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
    {{ page.metadata.summary }}
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

But probably more common and useful is to use `markdownReader`'s `pageProcessor` parameter.

``` swift
func pageProcessor(page: Page<EmptyMetadata>) {
  // Do whatever you want with the Page
  page.title.append("!")
}

try Saga(input: "content", output: "deploy")
  .register(
    metadata: EmptyMetadata.self,
    readers: [.markdownReader(pageProcessor: pageProcessor)],
    writers: [.pageWriter(template: "page.html")]
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
    .package(name: "Saga", url: "https://github.com/loopwerk/Saga.git", from: "0.7.0"),
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

- Add paginating support for list/tag/year writers.
- Research a way to auto-run on changes, maybe even reloading the browser as well.
- Docs and tests.

## Known limitations

- Stencil, the template language, doesn't support rendering computed properties (https://github.com/stencilproject/Stencil/issues/219). So if you extend `Page` with computed properties, you sadly won't be able to render them in your templates.
- Stencil's template inheritance doesn't support overriding blocks through multiple levels (https://github.com/stencilproject/Stencil/issues/275)

## Thanks

Inspiration for the API of Saga is very much owed to my favorite (but sadly long unmaintained) static site generator: [liquidluck](https://github.com/avelino/liquidluck). Its system of multiple readers and writers is really good and I wanted something similar.

Thanks also goes to [Publish](https://github.com/JohnSundell/Publish), another static site generator written in Swift, for inspiring me towards custom strongly typed metadata. A huge thanks also for its metadata decoder, which was copied over shamelessly.

## FAQ

Q: Is this ready for production?  
A: Almost, but not quite. This is still in early development, and the API is very much subject to change until Saga reaches 1.0.0. I still use [liquidluck](https://github.com/avelino/liquidluck) for my own static sites, which should tell you enough.

Q: How do I view the generated website?  
A: Personally I use the `serve` tool, installed via Homebrew or NPM, simply run `serve deploy` from within the Example folder.
