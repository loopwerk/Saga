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
  var isPublicArticle: Bool {
    guard let metadata = metadata as? ArticleMetadata else {
      return false
    }
    return metadata.isPublic
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
      .section(prefix: "articles", filter: { $0.isPublicArticle }, writers: [
        .pageWriter(template: "article.html"),
        .listWriter(template: "articles.html"),
        .tagWriter(template: "tag.html", tags: { $0.tags }),
        .yearWriter(template: "year.html"),
      ]),

      // The section writer above does exactly the same as the following lines would do:
      //
      // .pageWriter(template: "article.html", filter: { $0.isPublicArticle }),
      // .listWriter(template: "articles.html", output: "articles/index.html", filter: { $0.isPublicArticle }),
      // .tagWriter(template: "tag.html", output: "articles/[tag]/index.html", tags: { $0.tags }, filter: { $0.isPublicArticle }),
      // .yearWriter(template: "year.html", output: "articles/[year]/index.html", filter: { $0.isPublicArticle }),
      //
      // So it basically prefixes the `output` and pre-filters the pages so you don't have to do it for every writer.

      // Apps
      .listWriter(template: "apps.html", output: "apps/index.html", filter: { $0.isApp }),

      // Other pages
      // We specifically filter on EmptyMetadata here, otherwise it might process articles or apps that were not written by the writers above.
      // For example, where is one article that is not public, so wouldn't have been written by that first pageWriter. That means all of a
      // sudden this "less specific" pageWriter would now still write that article to disk, which is not what we want.
      .pageWriter(template: "page.html", filter: { $0.metadata is EmptyMetadata }),
    ]
  )
  .staticFiles()
