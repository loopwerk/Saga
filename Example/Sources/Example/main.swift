import Foundation
import Saga
import SagaImageReader
import SagaParsleyMarkdownReader
import SagaPathKit
import SagaSwimRenderer

enum SiteMetadata {
  static let url = URL(string: "http://www.example.com")!
  static let name = "Example website"
  static let author = "Kevin Renskers"
}

struct ArticleMetadata: Metadata {
  let tags: [String]
  var summary: String?
  let archived: Bool?
}

struct AppMetadata: Metadata {
  let url: URL?
  let images: [String]?
}

struct MusicVideoMetadata: Metadata {
  let artworkUrl: String
  let previewUrl: String
  let trackViewUrl: String
  let artistName: String
}

struct AlbumMetadata: Metadata {}
struct PhotoMetadata: Metadata {}

struct ArtistMetadata: Metadata {
  let genre: String
  let image: String
}

struct MusicAlbumMetadata: Metadata {
  let year: Int
  let cover: String
}

struct TrackMetadata: Metadata {
  let duration: String
  var trackNumber: Int?
  let youtube: String?
}

/// An easy way to check if an article is archived, since ArticleMetadata.archived is optional
extension Item where M == ArticleMetadata {
  var archived: Bool {
    return metadata.archived ?? false
  }
}

extension Item where M == TrackMetadata {
  var trackNumber: Int {
    return metadata.trackNumber ?? 0
  }
}

/// An item processor that extracts the track number from filenames like "07-here-comes-the-sun"
/// and strips it from the destination path.
@Sendable func trackNumberInFilename(item: Item<TrackMetadata>) async {
  item.metadata.trackNumber = Int(item.filenameWithoutExtension.prefix(2))

  if item.title == item.filenameWithoutExtension {
    let stripped = String(item.filenameWithoutExtension.dropFirst(3))
    item.title = stripped.replacingOccurrences(of: "-", with: " ")
  }
}

try await Saga(input: "content", output: "deploy")
  // All non-archived articles are included in lists and feeds.
  // Using claimExcludedItems: false so the archived articles remain available
  // for the next step, which renders their individual pages.
  .register(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.parsleyMarkdownReader],
    itemProcessor: Saga.publicationDateInFilename,
    filter: { !$0.archived },
    claimExcludedItems: false,
    writers: [
      .itemWriter(swim(renderArticle)),
      .listWriter(swim(renderArticles), paginate: 5),
      .tagWriter(swim(renderPartition), paginate: 5, tags: \.metadata.tags),
      .yearWriter(swim(renderPartition)),

      // Atom feed for all articles, and a feed per tag
      .listWriter(Saga.atomFeed(title: SiteMetadata.name, author: SiteMetadata.author, baseURL: SiteMetadata.url, summary: \.metadata.summary), output: "feed.xml"),
      .tagWriter(Saga.atomFeed(title: SiteMetadata.name, author: SiteMetadata.author, baseURL: SiteMetadata.url, summary: \.metadata.summary), output: "tag/[key]/feed.xml", tags: \.metadata.tags),
    ]
  )

  // Archived articles still get their own page, but are not in any lists or feeds.
  .register(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.parsleyMarkdownReader],
    itemProcessor: Saga.publicationDateInFilename,
    writers: [
      .itemWriter(swim(renderArticle)),
    ]
  )

  // All markdown files within the "apps" subfolder will be parsed to html,
  // using AppMetadata as the Item's metadata type.
  .register(
    folder: "apps",
    metadata: AppMetadata.self,
    readers: [.parsleyMarkdownReader],
    writers: [.listWriter(swim(renderApps))]
  )

  // Photo albums from markdown files, with nested photo pages per album
  .register(
    folder: "photos",
    metadata: AlbumMetadata.self,
    readers: [.parsleyMarkdownReader],
    writers: [
      .listWriter(swim(renderAlbums)),
      .itemWriter(swim(renderAlbum)),
    ],
    nested: { nested in
      nested.register(
        metadata: PhotoMetadata.self,
        readers: [.imageReader],
        writers: [
          .itemWriter(swim(renderPhoto)),
        ]
      )
    }
  )

  // Music catalog: Artists → Albums → Tracks (three levels of nesting)
  .register(
    folder: "music",
    metadata: ArtistMetadata.self,
    readers: [.parsleyMarkdownReader],
    writers: [
      .listWriter(swim(renderArtists)),
      .itemWriter(swim(renderArtist)),
    ],
    nested: { artists in
      artists.register(
        metadata: MusicAlbumMetadata.self,
        readers: [.parsleyMarkdownReader],
        writers: [
          .itemWriter(swim(renderMusicAlbum)),
        ],
        nested: { albums in
          albums.register(
            folder: "tracks",
            metadata: TrackMetadata.self,
            readers: [.parsleyMarkdownReader],
            itemProcessor: trackNumberInFilename,
            sorting: { $0.trackNumber < $1.trackNumber },
            writers: [
              .itemWriter(swim(renderTrack)),
            ]
          )
        }
      )
    }
  )

  // Fetch Beatles videos from iTunes and render them
  .register(
    metadata: MusicVideoMetadata.self,
    fetch: fetchBeatlesVideos,
    writers: [
      .itemWriter(swim(renderVideo)),
      .listWriter(swim(renderBeatles), output: "videos/index.html"),
    ]
  )

  // All the remaining markdown files will be parsed to html,
  // using the default EmptyMetadata as the Item's metadata type.
  .register(
    metadata: EmptyMetadata.self,
    readers: [.parsleyMarkdownReader],
    writers: [.itemWriter(swim(renderPage))]
  )

  // Sitemap including all generated pages
  .createPage("sitemap.xml", using: Saga.sitemap(baseURL: SiteMetadata.url))

  // Run the steps we registered above.
  // Static files (images, css, etc.) are copied automatically.
  .run()
