import Foundation
import Saga
import PathKit
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

// An example of a simple page processor that takes files such as "2021-01-27-post-with-date-in-filename"
// and uses the date within the filename as the publication date.
func itemProcessor(item: Item<ArticleMetadata>) async {
  // If the filename starts with a valid date, use that as the Page's date and strip it from the destination path
  let first10 = String(item.relativeSource.lastComponentWithoutExtension.prefix(10))
  guard first10.count == 10, let date = Run.pageProcessorDateFormatter.date(from: first10) else {
    return
  }

  // Set the date
  item.published = date

  // And remove the first 11 characters from the filename
  let first11 = String(item.relativeSource.lastComponentWithoutExtension.prefix(11))
  item.relativeDestination = Path(
    item.relativeSource.string.replacingOccurrences(of: first11, with: "")
  ).makeOutputPath(itemWriteMode: .moveToSubfolder)
}

@main
struct Run {
  static var pageProcessorDateFormatter: DateFormatter = {
    let pageProcessorDateFormatter = DateFormatter()
    pageProcessorDateFormatter.dateFormat = "yyyy-MM-dd"
    pageProcessorDateFormatter.timeZone = .current
    return pageProcessorDateFormatter
  }()

  static func main() async throws {
    try await Saga(input: "content", output: "deploy")
      // All markdown files within the "articles" subfolder will be parsed to html,
      // using ArticleMetadata as the Item's metadata type.
      // Furthermore we are only interested in public articles.
      .register(
        folder: "articles",
        metadata: ArticleMetadata.self,
        readers: [.parsleyMarkdownReader()],
        itemProcessor: itemProcessor,
        filter: \.public,
        writers: [
          .itemWriter(swim(renderArticle)),
          .listWriter(swim(renderArticles), paginate: 5),
          .tagWriter(swim(renderPartition), paginate: 5, tags: \.metadata.tags),
          .yearWriter(swim(renderPartition)),

          // Atom feed for all articles, and a feed per tag
          .listWriter(swim(renderFeed), output: "feed.xml"),
          .tagWriter(swim(renderTagFeed), output: "tag/[key]/feed.xml", tags: \.metadata.tags),
        ]
      )

      // All markdown files within the "apps" subfolder will be parsed to html,
      // using AppMetadata as the Item's metadata type.
      .register(
        folder: "apps",
        metadata: AppMetadata.self,
        readers: [.parsleyMarkdownReader()],
        writers: [.listWriter(swim(renderApps))]
      )

      // All the remaining markdown files will be parsed to html,
      // using the default EmptyMetadata as the Item's metadata type.
      .register(
        metadata: EmptyMetadata.self,
        readers: [.parsleyMarkdownReader()],
        writers: [.itemWriter(swim(renderPage))]
      )

      // Run the steps we registered above
      .run()

      // All the remaining files that were not parsed to markdown, so for example images, raw html files and css,
      // are copied as-is to the output folder.
      .staticFiles()
  }
}
