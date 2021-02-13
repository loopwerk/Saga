import HTML
import Saga
import Foundation

func baseHtml(siteMetadata: SiteMetadata, title pageTitle: String, @NodeBuilder children: () -> NodeConvertible) -> Node {
  html(lang: "en-US") {
    head {
      title { siteMetadata.name+": "+pageTitle }
      link(href: "/static/style.css", rel: "stylesheet")
      link(href: "/static/prism.css", rel: "stylesheet")
    }
    body {
      nav {
        a(href: "/") { "Home" }
        a(href: "/articles/") { "Articles" }
        a(href: "/apps/") { "Apps" }
        a(href: "/about.html") { "About" }
      }
      div(id: "content") {
        children()
      }
      script(src: "https://cdnjs.cloudflare.com/ajax/libs/prism/1.23.0/components/prism-core.min.js")
      script(src: "https://cdnjs.cloudflare.com/ajax/libs/prism/1.23.0/plugins/autoloader/prism-autoloader.min.js")
    }
  }
}

extension Date {
  func formatted(_ format: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = format
    return formatter.string(from: self)
  }
}

func renderArticle(context: PageRenderingContext<ArticleMetadata, SiteMetadata>) -> Node {
  return baseHtml(siteMetadata: context.siteMetadata, title: context.page.title) {
    div(id: "article") {
      h1 { context.page.title }
      h2 {
        context.page.date.formatted("dd MMMM")+", "
        a(href: "/articles/\(context.page.date.formatted("yyyy"))/") { context.page.date.formatted("yyyy") }
      }
      ul {
        context.page.metadata.tags.map { tag in
          li {
            a(href: "/articles/tag/\(tag.slugified)/") { tag }
          }
        }
      }
      context.page.body
    }
  }
}

func articleInList(_ article: Page<ArticleMetadata>) -> Node {
  div(class: "article") {
    a(href: article.url) { article.title }

    p {
      if let summary = article.metadata.summary {
        summary
      } else {
        String(article.body.withoutHtmlTags.prefix(255))
      }
    }
  }
}

@NodeBuilder
func renderPagination(_ paginator: Paginator?) -> Node {
  if let paginator = paginator, paginator.numberOfPages > 1 {
    div(class: "pagination") {
      p {
        "Page \(paginator.index) out of \(paginator.numberOfPages)"
      }
      if let previous = paginator.previous {
        a(href: previous.url) { "Previous page" }
      }
      if let next = paginator.next {
        a(href: next.url) { "Next page" }
      }
    }
  }
}

func renderArticles(context: PagesRenderingContext<ArticleMetadata, SiteMetadata>) -> Node {
  baseHtml(siteMetadata: context.siteMetadata, title: "Articles") {
    h1 { "Articles" }
    context.pages.map(articleInList)
    renderPagination(context.paginator)
  }
}

func renderPartition<T>(context: PartitionedRenderingContext<T, ArticleMetadata, SiteMetadata>) -> Node {
  baseHtml(siteMetadata: context.siteMetadata, title: "Articles in \(context.key)") {
    h1 { "Articles in \(context.key)" }
    context.pages.map(articleInList)
    renderPagination(context.paginator)
  }
}

func renderPage(context: PageRenderingContext<EmptyMetadata, SiteMetadata>) -> Node {
  baseHtml(siteMetadata: context.siteMetadata, title: context.page.title) {
    div(id: "page") {
      h1 { context.page.title }
      context.page.body

      if context.page.relativeDestination == "about.html" {
        h1 { "Apps I've built" }
        context.allPages.compactMap { $0 as? Page<AppMetadata> }.map { app in
          p { app.title }
        }
      }
    }
  }
}

func renderApps(context: PagesRenderingContext<AppMetadata, SiteMetadata>) -> Node {
  baseHtml(siteMetadata: context.siteMetadata, title: "Apps") {
    h1 { "Apps" }
    context.pages.map { app in
      div(class: "app") {
        h2 { app.title }

        if let images = app.metadata.images {
          images.map { image in
            img(src: image)
          }
        }

        app.body

        if let url = app.metadata.url {
          p {
            a(href: url.absoluteString) { "App Store" }
          }
        }
      }
    }
  }
}
