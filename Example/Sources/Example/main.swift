import Foundation
import Saga
import PathKit

struct ArticleMetadata: Metadata {
  let tags: [String]
  let summary: String?
  let `public`: Bool?
}

struct AppMetadata: Metadata {
  let url: URL?
  let images: [String]?
}

// SiteMetadata is given to every template.
// You can put whatever you want in here, as long as it's Decodable.
struct SiteMetadata: Metadata {
  let url: URL
  let name: String
}

let siteMetadata = SiteMetadata(
  url: URL(string: "http://www.example.com")!,
  name: "Example website"
)

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
  ).makeOutputPath(keepExactPath: false)
}

try Saga(input: "content", output: "deploy", templates: "templates", siteMetadata: siteMetadata)
  // All markdown files within the "articles" subfolder will be parsed to html,
  // using ArticleMetadata as the Page's metadata type.
  // Furthermore we are only interested in public articles.
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
  // All markdown files within the "apps" subfolder will be parsed to html,
  // using AppMetadata as the Page's metadata type.
  .register(
    folder: "apps",
    metadata: AppMetadata.self,
    readers: [.markdownReader()],
    writers: [.listWriter(template: "apps.html")]
  )
  // All the remaining markdown files will be parsed to html,
  // using the default EmptyMetadata as the Page's metadata type.
  .register(
    metadata: EmptyMetadata.self,
    readers: [.markdownReader()],
    writers: [.pageWriter(template: "page.html", keepExactPath: true)]
  )
  // Run the steps we registered above
  .run()
  // All the remaining files that were not parsed to markdown, so for example images, raw html files and css,
  // are copied as-is to the output folder.
  .staticFiles()
  // Create Twitter preview images for all articles. This only works if you have Python installed with the Pillow dependency.
  .createArticleImages()


extension Saga {
  private func run(_ cmd: String) -> String? {
    let pipe = Pipe()
    let process = Process()
    process.launchPath = "/bin/sh"
    process.arguments = ["-c", String(format:"%@", cmd)]
    process.standardOutput = pipe
    let fileHandle = pipe.fileHandleForReading
    process.launch()
    return String(data: fileHandle.readDataToEndOfFile(), encoding: .utf8)
  }

  @discardableResult
  func createArticleImages() -> Self {
    let articles = fileStorage.compactMap { $0.page as? Page<ArticleMetadata> }

    for article in articles {
      let destination = self.outputPath + "static" + (article.filenameWithoutExtension + ".png")
      _ = run("cd \((self.rootPath + "ImageGenerator").string) && python image.py \"\(article.title)\" \"\(destination)\"")
    }

    return self
  }
}
