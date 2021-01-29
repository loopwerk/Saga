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
  // All the remaining files that were not parsed to markdown, so for example images, raw html files and css,
  // are copied as-is to the output folder.
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


## TODO

- Remove the page title from the page body - right now it's not possible to add content between the title and the body of an article, something that I do need for my own website.
- Add paginating support for list/tag/year writers.
- Replace the Ink and Splash dependencies (see known limitations, below).
- Docs and tests.

## Known limitations

- Stencil, the template language, doesn't support rendering computed properties (https://github.com/stencilproject/Stencil/issues/219). So if you extend `Page` with computed properties, you sadly won't be able to render them in your templates.
- Stencil's template inheritance doesn't support overriding blocks through multiple levels (https://github.com/stencilproject/Stencil/issues/275)
- Ink, the Markdown parser, is buggy and is missing features (https://github.com/JohnSundell/Ink/pull/49, https://github.com/JohnSundell/Ink/pull/63). Pull requests don't seem to get merged anymore?
- Splash, the syntax highlighter, only has support for Swift grammar. If you write articles with, let's say, JavaScript code blocks, they won't get properly highlighted.
