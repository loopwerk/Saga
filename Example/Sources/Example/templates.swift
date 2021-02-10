import HTML
import Saga
import Foundation

func baseHtml(siteMetadata: SiteMetadata, title pageTitle: String, @NodeBuilder children: () -> NodeConvertible) -> Node {
  html(lang: "en-US") {
    html {
      head {
        title {
          siteMetadata.name+": "+pageTitle
        }
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
      h1 {
        context.page.title
      }
      h2 {
        context.page.date.formatted("dd MMMM")+", "
        a(href: "/articles/\(context.page.date.formatted("yyyy"))/") { context.page.date.formatted("yyyy") }
      }
      ul {
        context.page.metadata.tags.map { tag in
          li {
            a(href: "/articles/tag/\(tag.slugify())/") {
              tag
            }
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

    if let summary = article.metadata.summary {
      p {
        summary
      }
    } else {
      String(article.body.toString().prefix(255))
    }
  }
}


func renderArticles(context: PagesRenderingContext<ArticleMetadata, SiteMetadata>) -> Node {
  baseHtml(siteMetadata: context.siteMetadata, title: "Articles") {
    h1 { "Articles" }
    context.pages.map(articleInList)

    h1 { "Apps" }
    context.allPages.compactMap { $0 as? Page<AppMetadata> }.map { app in
      p {
        app.title
      }
    }
  }
}

func renderTag(context: TagRenderingContext<ArticleMetadata, SiteMetadata>) -> Node {
  baseHtml(siteMetadata: context.siteMetadata, title: "Articles in \(context.tag)") {
    h1 { "Articles in \(context.tag)" }
    context.pages.map(articleInList)
  }
}

func renderYear(context: YearRenderingContext<ArticleMetadata, SiteMetadata>) -> Node {
  baseHtml(siteMetadata: context.siteMetadata, title: "Articles in \(context.year)") {
    h1 { "Articles in \(context.year)" }
    context.pages.map(articleInList)
  }
}

func renderPage(context: PageRenderingContext<EmptyMetadata, SiteMetadata>) -> Node {
  baseHtml(siteMetadata: context.siteMetadata, title: context.page.title) {
    div(id: "page") {
      h1 {
        context.page.title
      }
      context.page.body
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
