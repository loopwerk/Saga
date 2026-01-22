import Foundation
import PathKit
import Saga
import SagaParsleyMarkdownReader
import SagaSwimRenderer

enum SiteMetadata {
  static let url = URL(string: "http://www.example.com")!
  static let name = "Example website"
  static let author = "Kevin Renskers"
}

struct ArticleMetadata: Metadata {
  let tags: [String]
  var summary: String?
  let `public`: Bool?
}

struct AppMetadata: Metadata {
  let url: URL?
  let images: [String]?
}

// An easy way to only get public articles, since ArticleMetadata.public is optional
extension Item where M == ArticleMetadata {
  var `public`: Bool {
    return metadata.public ?? true
  }
}

@main
struct Run {
  static func main() async throws {
    try await Saga(input: "content", output: "deploy")
      // All markdown files within the "articles" subfolder will be parsed to html,
      // using ArticleMetadata as the Item's metadata type.
      // Furthermore we are only interested in public articles.
      .register(
        folder: "articles",
        metadata: ArticleMetadata.self,
        readers: [.parsleyMarkdownReader],
        itemProcessor: publicationDateInFilename,
        filter: \.public,
        writers: [
          .itemWriter(swim(renderArticle)),
          .listWriter(swim(renderArticles), paginate: 5),
          .tagWriter(swim(renderPartition), paginate: 5, tags: \.metadata.tags),
          .yearWriter(swim(renderPartition)),

          // Atom feed for all articles, and a feed per tag
          .listWriter(atomFeed(title: SiteMetadata.name, author: SiteMetadata.author, baseURL: SiteMetadata.url, summary: \.metadata.summary), output: "feed.xml"),
          .tagWriter(atomFeed(title: SiteMetadata.name, author: SiteMetadata.author, baseURL: SiteMetadata.url, summary: \.metadata.summary), output: "tag/[key]/feed.xml", tags: \.metadata.tags),
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

      .register(
        folder: "photos",
        readers: [.parsleyMarkdownReader],
        writers: [.itemWriter(swim(renderPhotos))]
      )

      // All the remaining markdown files will be parsed to html,
      // using the default EmptyMetadata as the Item's metadata type.
      .register(
        metadata: EmptyMetadata.self,
        readers: [.parsleyMarkdownReader],
        writers: [.itemWriter(swim(renderPage))]
      )

      // Run the steps we registered above
      .run()
      // All the remaining files that were not parsed to markdown, so for example images, raw html files and css,
      // are copied as-is to the output folder.
      .staticFiles()
  }
}
