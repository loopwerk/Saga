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

// Add some helper methods to the Page type that Saga provides
extension Page {
  var isArticle: Bool {
    return metadata is ArticleMetadata
  }
  var isPublicArticle: Bool {
    return (metadata as? ArticleMetadata)?.isPublic ?? false
  }
  var isApp: Bool {
    return metadata is AppMetadata
  }
  var tags: [String] {
    return (metadata as? ArticleMetadata)?.tags ?? []
  }
}

let pageProcessorDateFormatter = DateFormatter()
pageProcessorDateFormatter.dateFormat = "yyyy-MM-dd"
pageProcessorDateFormatter.timeZone = .current

// An example of a simple page processor that takes files such as "2021-01-27-post-with-date-in-filename"
// and uses the date within the filename as the publication date.
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
  // All markdown files within the "articles" subfolder will be parsed to html,
  // using ArticleMetadata as the Page's metadata type.
  .read(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.markdownReader(pageProcessor: pageProcessor)]
  )
  // All markdown files within the "apps" subfolder will be parsed to html,
  // using AppMetadata as the Page's metadata type.
  .read(
    folder: "apps",
    metadata: AppMetadata.self,
    readers: [.markdownReader()]
  )
  // All the remaining markdown files will be parsed to html,
  // using the default EmptyMetadata as the Page's metadata type.
  .read(
    metadata: EmptyMetadata.self,
    readers: [.markdownReader()]
  )
  // Now that we have read all the markdown pages, we're going to write
  // them all to disk using a variety of writers.
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
      // For example, there is one article that is not public, so wouldn't have been written by that first pageWriter. That means all of a
      // sudden this "less specific" pageWriter would now still write that article to disk, which is not what we want.
      .pageWriter(template: "page.html", filter: { $0.metadata is EmptyMetadata }),
    ]
  )
  // All the remaining files that were not parsed to markdown, so for example images, raw html files and css,
  // are copied as-is to the output folder.
  .staticFiles()
