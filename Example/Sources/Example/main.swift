import Foundation
import Saga
import PathKit
import ShellOut

struct ArticleMetadata: Metadata {
  let tags: [String]
  let summary: String?
  let `public`: Bool?
}

struct AppMetadata: Metadata {
  let url: URL?
  let images: [String]?
}

// An easy way to only get public articles, since ArticleMetadata.public is optional
extension Page where M == ArticleMetadata {
  var `public`: Bool {
    return metadata.public ?? true
  }
}

let pageProcessorDateFormatter = DateFormatter()
pageProcessorDateFormatter.dateFormat = "yyyy-MM-dd"
pageProcessorDateFormatter.timeZone = .current

// An example of a simple page processor that takes files such as "2021-01-27-post-with-date-in-filename"
// and uses the date within the filename as the publication date.
func pageProcessor(page: Page<ArticleMetadata>) {
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

try Saga(input: "content", output: "deploy", templates: "templates")
  .register(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.markdownReader(pageProcessor: pageProcessor)],
    filter: \.public,
    writers: [
      .pageWriter(template: "article.html"),
      .listWriter(template: "articles.html"),
      .tagWriter(template: "tag.html", tags: \.metadata.tags),
      .yearWriter(template: "year.html"),
    ]
  )
  .register(
    folder: "apps",
    metadata: AppMetadata.self,
    readers: [.markdownReader()],
    writers: [.listWriter(template: "apps.html")]
  )
  .register(
    metadata: EmptyMetadata.self,
    readers: [.markdownReader()],
    writers: [.pageWriter(template: "page.html")]
  )
  .run()
  .staticFiles()
  .createArticleImages()


extension Saga {
  @discardableResult
  func createArticleImages() -> Self {
    let articles = fileStorage.compactMap { $0.page as? Page<ArticleMetadata> }

    for article in articles {
      let destination = (self.outputPath + article.relativeDestination.parent()).string + ".png"
      _ = try? shellOut(to: "python image.py", arguments: ["\"\(article.title)\"", destination], at: (self.rootPath + "ImageGenerator").string)
    }

    return self
  }
}
