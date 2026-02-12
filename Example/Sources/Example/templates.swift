import Foundation
import HTML
import Moon
import Saga
import SagaSwimRenderer
import PathKit

// MARK: - Helpers

extension Date {
  func formatted(_ format: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = format
    return formatter.string(from: self)
  }
}

extension Item where M == ArticleMetadata {
  var summary: String {
    if let summary = metadata.summary {
      return summary
    }
    return String(body.withoutHtmlTags.prefix(255))
  }
}

func photosForAlbum(_ album: AnyItem, allItems: [AnyItem]) -> [AnyItem] {
  allItems
    .filter { $0 is Item<PhotoMetadata> && $0.relativeSource.parent() == album.relativeSource.parent() }
    .sorted { $0.relativeSource.lastComponent < $1.relativeSource.lastComponent }
}

// MARK: - Base layout

func baseHtml(title pageTitle: String, @NodeBuilder children: () -> NodeConvertible) -> Node {
  html(lang: "en-US") {
    head {
      meta(charset: "utf-8")
      meta(content: "width=device-width, initial-scale=1", name: "viewport")
      title { SiteMetadata.name + ": " + pageTitle }
      link(href: "/static/style.css", rel: "stylesheet")
      link(href: "/static/prism.css", rel: "stylesheet")
    }
    body {
      header {
        nav {
          a(class: "site-title", href: "/") { SiteMetadata.name }
          div(class: "nav-links") {
            a(href: "/articles/") { "Articles" }
            a(href: "/apps/") { "Apps" }
            a(href: "/photos/") { "Photos" }
            a(href: "/about/") { "About" }
          }
        }
      }
      main {
        children()
      }
      footer {
        p {
          "Built with"
          a(href: "https://github.com/loopwerk/Saga") { "Saga" }
        }
      }
    }
  }
}

// MARK: - Articles

func renderArticle(context: ItemRenderingContext<ArticleMetadata>) -> Node {
  return baseHtml(title: context.item.title) {
    div(class: "article-detail") {
      h1 { context.item.title }
      div(class: "article-meta") {
        context.item.date.formatted("dd MMMM") + ", "
        a(href: "/articles/\(context.item.date.formatted("yyyy"))/") { context.item.date.formatted("yyyy") }
      }
      ul(class: "tags") {
        context.item.metadata.tags.map { tag in
          li {
            a(href: "/articles/tag/\(tag.slugified)/") { tag }
          }
        }
      }
      div(class: "article-body") {
        Node.raw(Moon.shared.highlightCodeBlocks(in: context.item.body))
      }
    }
  }
}

func articleInList(_ article: Item<ArticleMetadata>) -> Node {
  div(class: "article-card") {
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
      if let previous = paginator.previous {
        a(class: "pagination-link", href: previous.url) { "\u{2190} Previous" }
      }
      span(class: "pagination-info") {
        "Page \(paginator.index) of \(paginator.numberOfPages)"
      }
      if let next = paginator.next {
        a(class: "pagination-link", href: next.url) { "Next \u{2192}" }
      }
    }
  }
}

func renderArticles(context: ItemsRenderingContext<ArticleMetadata>) -> Node {
  baseHtml(title: "Articles") {
    h1 { "Articles" }
    context.items.map(articleInList)
    renderPagination(context.paginator)
  }
}

func renderPartition<T>(context: PartitionedRenderingContext<T, ArticleMetadata>) -> Node {
  baseHtml(title: "Articles in \(context.key)") {
    h1 { "Articles in \(context.key)" }
    context.items.map(articleInList)
    renderPagination(context.paginator)
  }
}

// MARK: - Apps

func renderApps(context: ItemsRenderingContext<AppMetadata>) -> Node {
  baseHtml(title: "Apps") {
    h1 { "Apps" }
    context.items.map { app in
      div(class: "app-card") {
        h2 { app.title }

        if let images = app.metadata.images {
          div(class: "app-images") {
            images.map { image in
              img(src: image)
            }
          }
        }

        div(class: "article-body") {
          Node.raw(app.body)
        }

        if let url = app.metadata.url {
          p {
            a(class: "button", href: url.absoluteString) { "App Store" }
          }
        }
      }
    }
  }
}

// MARK: - Photo albums

func renderAlbums(context: ItemsRenderingContext<AlbumMetadata>) -> Node {
  baseHtml(title: "Photos") {
    div(class: "collections") {
      h1 { "Photos" }
      
      div(class: "collections-grid") {
        context.items.map { album in
          let photos = photosForAlbum(album, allItems: context.allItems)
          let previewPhotos = Array(photos.prefix(4))
          let folder = album.relativeSource.parent()
          
          return a(class: "collection-card", href: album.url) {
            div(class: "card-previews") {
              previewPhotos.map { photo in
                img(alt: "", loading: "lazy", src: "/\(folder)/\(photo.relativeSource.lastComponent)")
              }
            }
            div(class: "card-info") {
              h2 { album.title }
              p { "\(photos.count) photos" }
            }
          }
        }
      }
    }
  }
}

func renderAlbum(context: ItemRenderingContext<AlbumMetadata>) -> Node {
  let photos = photosForAlbum(context.item, allItems: context.allItems)

  return baseHtml(title: context.item.title) {
    div(class: "album") {
      h1 { context.item.title }

      if !context.item.body.isEmpty {
        div(class: "album-description") {
          Node.raw(context.item.body)
        }
      }

      div(class: "photo-grid") {
        photos.map { photo in
          a(class: "photo-item", href: photo.url) {
            img(alt: photo.title, loading: "lazy", src: photo.relativeSource.lastComponent)
          }
        }
      }
    }

    div(class: "back-link") {
      a(href: "/photos/") { "Back to Photos" }
    }
  }
}

func renderPhoto(context: ItemRenderingContext<PhotoMetadata>) -> Node {
  let album = context.allItems.first {
    $0 is Item<AlbumMetadata> && $0.relativeSource.parent() == context.item.relativeSource.parent()
  }

  let siblings = context.items
    .filter { $0.relativeSource.parent() == context.item.relativeSource.parent() }
    .sorted { $0.relativeSource.lastComponent < $1.relativeSource.lastComponent }
  let currentIndex = siblings.firstIndex(where: { $0 === context.item })

  let previous = currentIndex.flatMap { $0 > 0 ? siblings[$0 - 1] : nil }
  let next = currentIndex.flatMap { $0 < siblings.count - 1 ? siblings[$0 + 1] : nil }

  let imageSrc = "../\(context.item.relativeSource.lastComponent)"

  return baseHtml(title: context.item.title) {
    div(class: "photo-page") {
      div(class: "photo-nav") {
        if let previous = previous {
          a(class: "nav-prev", href: previous.url) { "\u{2190}" }
        }

        if let album = album {
          a(class: "nav-close", href: album.url) { "\u{2715}" }
        }

        if let next = next {
          a(class: "nav-next", href: next.url) { "\u{2192}" }
        }
      }

      div(class: "photo-full") {
        img(alt: context.item.title, src: imageSrc)
      }
    }
  }
}

// MARK: - Generic pages

func renderPage(context: ItemRenderingContext<EmptyMetadata>) -> Node {
  baseHtml(title: context.item.title) {
    div(class: "page") {
      h1 { context.item.title }
      div(class: "article-body") {
        Node.raw(Moon.shared.highlightCodeBlocks(in: context.item.body))
      }

      if context.item.relativeDestination == "about.html" {
        h2 { "Apps I've built" }
        context.allItems.compactMap { $0 as? Item<AppMetadata> }.map { app in
          p { app.title }
        }
      }
    }
  }
}
