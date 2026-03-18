# Reusable HTML Layouts

Create a shared HTML shell and reuse it across all your templates.

## Overview

Most pages on a website share the same outer HTML structure: `<html>`, `<head>`, navigation, footer. Rather than duplicating this in every template, define a base layout function and call it from each renderer.

This guide uses [SagaSwimRenderer](https://github.com/loopwerk/SagaSwimRenderer), which wraps the [Swim](https://github.com/robb/Swim) library for type-safe HTML using Swift's result builders. The `Node`, `@NodeBuilder`, and HTML element functions like `html`, `head`, `body`, etc. all come from Swim's `HTML` module.

## Defining a base layout

Create a function that accepts a title, optional extras for the `<head>`, and a `@NodeBuilder` closure for page content:

```swift
import HTML

func baseLayout(
  title pageTitle: String,
  @NodeBuilder extraHead: () -> NodeConvertible = { Node.fragment([]) },
  @NodeBuilder content: () -> NodeConvertible
) -> Node {
  return [
    Node.documentType("html"),
    html(lang: "en-US") {
      head {
        meta(charset: "utf-8")
        meta(content: "width=device-width, initial-scale=1", name: "viewport")
        title { pageTitle }
        link(href: Saga.hashed("/static/style.css"), rel: "stylesheet")
        extraHead()
      }
      body {
        nav {
          a(href: "/") { "Home" }
          a(href: "/articles/") { "Articles" }
          a(href: "/about/") { "About" }
        }
        main {
          content()
        }
        footer {
          p { "Built with Saga" }
        }
      }
    },
  ]
}
```

> Tip: The `extraHead` parameter is handy for injecting page-specific metadata like Open Graph tags or scripts for a single page.

## Using the layout in templates

Each rendering function calls `baseLayout` and supplies its page-specific content:

```swift
func renderArticle(context: ItemRenderingContext<ArticleMetadata>) -> Node {
  baseLayout(title: context.item.title) {
    article {
      h1 { context.item.title }
      p { context.item.metadata.summary ?? "" }
      Node.raw(context.item.body)
    }
  }
}

func renderArticles(context: ItemsRenderingContext<ArticleMetadata>) -> Node {
  baseLayout(title: "Articles") {
    h1 { "Articles" }
    ul {
      context.items.map { item in
        li {
          a(href: item.url) { item.title }
        }
      }
    }
  }
}
```

Pages that need extra `<head>` content can pass it via `extraHead`:

```swift
func renderSearch(context: PageRenderingContext) -> Node {
  baseLayout(
    title: "Search",
    extraHead: {
      script(src: "/pagefind/pagefind-modular-ui.js")
    }
  ) {
    h1 { "Search" }
    input(id: "search", name: "q", placeholder: "Search articles", type: "text")
    div(id: "results")
  }
}
```

## File organization

A common pattern is to keep the base layout in its own file and each template in a separate file:

```
Sources/
  MySite/
    templates/
      BaseLayout.swift
      RenderArticle.swift
      RenderArticles.swift
      RenderPage.swift
    main.swift
```
