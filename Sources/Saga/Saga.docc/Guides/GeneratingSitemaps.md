# Generating a Sitemap

Create an XML sitemap for search engines.

## Overview

A sitemap tells search engines which pages exist on your site and how often they change. Since Saga's ``Saga/createPage(_:using:)`` has access to all items across all steps, you can generate a complete `sitemap.xml` with a few lines of code.

## Create the sitemap renderer

Write a function that takes a ``PageRenderingContext`` and returns the sitemap XML as a `String`:

```swift
import Saga

func renderSitemap(context: PageRenderingContext) -> String {
  let baseURL = "https://example.com"

  var xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      <url>
        <loc>\(baseURL)/</loc>
      </url>

    """

  for item in context.allItems {
    xml += """
        <url>
          <loc>\(baseURL)\(item.url)</loc>
          <lastmod>\(formatDate(item.date))</lastmod>
        </url>

      """
  }

  xml += "</urlset>"
  return xml
}

private func formatDate(_ date: Date) -> String {
  let formatter = DateFormatter()
  formatter.dateFormat = "yyyy-MM-dd"
  formatter.timeZone = TimeZone(identifier: "UTC")
  return formatter.string(from: date)
}
```

## Register it as a page

Add the sitemap after your other registrations so that `allItems` is fully populated:

```swift
try await Saga(input: "content", output: "deploy")
  .register(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.parsleyMarkdownReader],
    writers: [
      .itemWriter(swim(renderArticle)),
      .listWriter(swim(renderArticles)),
    ]
  )
  .register(
    folder: "apps",
    metadata: AppMetadata.self,
    readers: [.parsleyMarkdownReader],
    writers: [.listWriter(swim(renderApps))]
  )
  .createPage("sitemap.xml", using: renderSitemap)
  .run()
```

## Adding static pages

The sitemap above only includes items. To include static pages (homepage, about, etc.), add them manually:

```swift
func renderSitemap(context: PageRenderingContext) -> String {
  let baseURL = "https://example.com"
  let staticPages = ["/", "/about/", "/contact/"]

  var xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">

    """

  for page in staticPages {
    xml += """
        <url>
          <loc>\(baseURL)\(page)</loc>
        </url>

      """
  }

  for item in context.allItems {
    xml += """
        <url>
          <loc>\(baseURL)\(item.url)</loc>
          <lastmod>\(formatDate(item.date))</lastmod>
        </url>

      """
  }

  xml += "</urlset>"
  return xml
}
```

> tip: Don't forget to reference your sitemap in `robots.txt`: `Sitemap: https://example.com/sitemap.xml`
