import Foundation
import HTML
import Moon
import Saga
import SagaPathKit
import SagaSwimRenderer

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

// MARK: - Base layout

func baseHtml(title pageTitle: String, @NodeBuilder children: () -> NodeConvertible) -> Node {
  html(lang: "en-US") {
    head {
      meta(charset: "utf-8")
      meta(content: "width=device-width, initial-scale=1", name: "viewport")
      title { SiteMetadata.name + ": " + pageTitle }
      link(href: Saga.hashed("/static/style.css"), rel: "stylesheet")
      link(href: Saga.hashed("/static/prism.css"), rel: "stylesheet")
    }
    body {
      header {
        nav {
          a(class: "site-title", href: "/") { SiteMetadata.name }
          div(class: "nav-links") {
            a(href: "/articles/") { "Articles" }
            a(href: "/apps/") { "Apps" }
            a(href: "/photos/") { "Photos" }
            a(href: "/music/") { "Music" }
            a(href: "/videos/") { "Videos" }
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
  if let paginator, paginator.numberOfPages > 1 {
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

func renderPartition(context: PartitionedRenderingContext<some Any, ArticleMetadata>) -> Node {
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
          let photos = album.children(as: PhotoMetadata.self)
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
  let photos = context.item.children(as: PhotoMetadata.self)

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
  let album = context.item.parent(as: AlbumMetadata.self)

  let imageSrc = "../\(context.item.relativeSource.lastComponent)"

  return baseHtml(title: context.item.title) {
    div(class: "detail-page") {
      div(class: "detail-nav") {
        if let previous = context.previous {
          a(class: "nav-prev", href: previous.url) { "\u{2190}" }
        }

        a(class: "nav-close", href: album.url) { "\u{2715}" }

        if let next = context.next {
          a(class: "nav-next", href: next.url) { "\u{2192}" }
        }
      }

      div(class: "photo-full") {
        img(alt: context.item.title, src: imageSrc)
      }
    }
  }
}

// MARK: - Music catalog (Artists → Albums → Tracks)

func renderArtists(context: ItemsRenderingContext<ArtistMetadata>) -> Node {
  baseHtml(title: "Music") {
    div(class: "page") {
      h1 { "Music" }
      p(class: "") { "An example of nested-in-nested processing steps." }
    }
    div(class: "collections-grid") {
      context.items.map { artist in
        a(class: "artist-card", href: artist.url) {
          img(alt: artist.title, class: "artist-image", src: artist.metadata.image)
          div(class: "card-info") {
            h2 { artist.title }
            p(class: "genre") { artist.metadata.genre }
            p { "\(artist.children.count) albums" }
          }
        }
      }
    }
  }
}

func renderArtist(context: ItemRenderingContext<ArtistMetadata>) -> Node {
  let albums = context.item.children(as: MusicAlbumMetadata.self)

  return baseHtml(title: context.item.title) {
    h1 { context.item.title }
    p(class: "subtitle") { context.item.metadata.genre }

    if !context.item.body.isEmpty {
      div(class: "album-description") {
        Node.raw(context.item.body)
      }
    }

    h2 { "Albums" }
    div(class: "collections-grid") {
      albums.map { album in
        a(class: "album-card", href: album.url) {
          img(alt: album.title, class: "album-cover-img", src: album.metadata.cover)
          div(class: "card-info") {
            h3 { album.title }
            p { "\(album.metadata.year) · \(album.children.count) tracks" }
          }
        }
      }
    }

    div(class: "back-link") {
      a(href: "/music/") { "Back to Music" }
    }
  }
}

func renderMusicAlbum(context: ItemRenderingContext<MusicAlbumMetadata>) -> Node {
  let artist = context.item.parent(as: ArtistMetadata.self)
  let tracks = context.item.children(as: TrackMetadata.self)

  return baseHtml(title: "\(context.item.title) — \(artist.title)") {
    div(class: "album-header") {
      img(alt: context.item.title, class: "album-cover-large", src: context.item.metadata.cover)
      div(class: "album-header-info") {
        h1 { context.item.title }
        p(class: "subtitle") {
          a(href: artist.url) { artist.title }
          " · \(context.item.metadata.year)"
        }
        if !context.item.body.isEmpty {
          div(class: "album-description") {
            Node.raw(context.item.body)
          }
        }
      }
    }

    ol(class: "track-list") {
      tracks.map { track in
        li(value: "\(track.trackNumber)") {
          a(class: "track-title", href: track.url) { track.title }
          span(class: "track-duration") { track.metadata.duration }
        }
      }
    }

    div(class: "back-link") {
      a(href: artist.url) { "Back to \(artist.title)" }
    }
  }
}

func renderTrack(context: ItemRenderingContext<TrackMetadata>) -> Node {
  let album = context.item.parent(as: MusicAlbumMetadata.self)
  let artist = album.parent(as: ArtistMetadata.self)

  return baseHtml(title: "\(context.item.title) — \(artist.title)") {
    div(class: "detail-page") {
      div(class: "detail-nav") {
        if let previous = context.previous {
          a(class: "nav-prev", href: previous.url) { "\u{2190}" }
        }

        a(class: "nav-close", href: album.url) { "\u{2715}" }

        if let next = context.next {
          a(class: "nav-next", href: next.url) { "\u{2192}" }
        }
      }

      if let youtubeId = context.item.metadata.youtube {
        div(class: "video-embed") {
          Node.raw("<iframe src=\"https://www.youtube.com/embed/\(youtubeId)\" frameborder=\"0\" allowfullscreen></iframe>")
        }
      }

      div(class: "track-detail") {
        h1 { context.item.title }
        p(class: "subtitle") {
          context.item.metadata.duration
        }
        p {
          "Track \(context.item.trackNumber) on"
          a(href: album.url) { album.title }
          " by "
          a(href: artist.url) { artist.title }
          " (\(album.metadata.year))"
        }
      }
    }
  }
}

// MARK: - Beatles videos

func renderBeatles(context: ItemsRenderingContext<MusicVideoMetadata>) -> Node {
  baseHtml(title: "Beatles Videos") {
    h1 { "Beatles Videos" }
    div(class: "video-grid") {
      context.items.map { video in
        a(class: "video-card", href: video.url) {
          img(alt: video.title, loading: "lazy", src: video.metadata.artworkUrl)
          div(class: "video-info") {
            h3 { video.title }
            p { "\(video.metadata.artistName) (\(video.date.formatted("yyyy")))" }
          }
        }
      }
    }
  }
}

func renderVideo(context: ItemRenderingContext<MusicVideoMetadata>) -> Node {
  baseHtml(title: context.item.title) {
    div(class: "detail-page") {
      div(class: "detail-nav") {
        if let previous = context.previous {
          a(class: "nav-prev", href: previous.url) { "\u{2190}" }
        }

        a(class: "nav-close", href: "/videos/") { "\u{2715}" }

        if let next = context.next {
          a(class: "nav-next", href: next.url) { "\u{2192}" }
        }
      }

      div(class: "video-detail") {
        video(controls: true, preload: "metadata") {
          source(src: context.item.metadata.previewUrl, type: "video/mp4")
        }
        h1 { context.item.title }
        p(class: "video-meta") {
          "\(context.item.metadata.artistName) (\(context.item.date.formatted("yyyy")))"
        }
        p {
          a(href: context.item.metadata.trackViewUrl, target: "_blank") { "View on Apple Music" }
        }
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
