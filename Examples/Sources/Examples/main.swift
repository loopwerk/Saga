import Foundation
import Saga
import PathKit

struct ArticleMetadata: Metadata {
  let tags: [String]
  let summary: String?
  let `public`: Bool?

  var isPublic: Bool {
    return `public` ?? true
  }
}

struct AppMetadata: Metadata {
  let url: URL?
  let images: [String]?
}

extension Page {
  var isArticle: Bool {
    return metadata is ArticleMetadata
  }
  var isApp: Bool {
    return metadata is AppMetadata
  }
  var tags: [String] {
    if let tagMetadata = metadata as? ArticleMetadata {
      return tagMetadata.tags
    }
    return []
  }
}

let pageProcessorDateFormatter = DateFormatter()
pageProcessorDateFormatter.dateFormat = "yyyy-MM-dd"
pageProcessorDateFormatter.timeZone = .current

func pageProcessor(page: Page) {
  // If the filename starts with a valid date, use that as the Page's date and strip it from the destination path
  let first10 = String(page.relativeSource.lastComponentWithoutExtension.prefix(10))
  guard first10.count == 10, let date = pageProcessorDateFormatter.date(from: first10) else {
    return
  }

  // Set the date
  page.date = date

  // And remove the first 11 characters from the filename
  let first11 = String(page.relativeSource.lastComponentWithoutExtension.prefix(11))
  page.relativeDestination = Path(
    page.relativeSource.string.replacingOccurrences(of: first11, with: "")
  ).makeOutputPath()
}

try Saga(input: "content", output: "deploy")
  .read(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.markdownReader(pageProcessor: pageProcessor)]
  )
  .read(
    folder: "apps",
    metadata: AppMetadata.self,
    readers: [.markdownReader()]
  )
  .read(
    metadata: EmptyMetadata.self,
    readers: [.markdownReader()]
  )
  .write(
    templates: "templates",
    writers: [
      // Articles
      .section(folder: "articles", filter: { $0.isArticle }, writers: [
        .pageWriter(template: "article.html"),
        .listWriter(template: "articles.html"),
        .tagWriter(template: "tag.html", tags: { $0.tags }),
        .yearWriter(template: "year.html"),
      ]),

      // The section writer above does exactly the same as the following lines would do:
      // .pageWriter(template: "article.html", filter: { $0.isArticle }),
      // .listWriter(template: "articles.html", output: "articles/index.html", filter: { $0.isArticle }),
      // .tagWriter(template: "tag.html", output: "articles/[tag]/index.html", tags: { $0.tags }, filter: { $0.isArticle }),
      // .yearWriter(template: "year.html", output: "articles/[year]/index.html", filter: { $0.isArticle }),

      // Apps
      .listWriter(template: "apps.html", output: "apps/index.html", filter: { $0.isApp }),

      // Other pages - we need to specifically exclude apps since those are not handled
      // by their own pageWriter and would therefore be picked up by this pageWriter,
      // which we don't want (apps are only shown as a list page, not separate pages).
      .pageWriter(template: "page.html", filter: { !$0.isApp }),
    ]
  )
  .staticFiles()
