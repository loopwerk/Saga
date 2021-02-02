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

// Add some helper methods to the Page type that Saga provides
extension Page where M == ArticleMetadata {
  var `public`: Bool {
    return metadata.public ?? true
  }
}

extension AnyPage {
  var isArticle: Bool {
    return self as? Page<ArticleMetadata> != nil
  }
  var isPublicArticle: Bool {
    return (self as? Page<ArticleMetadata>)?.public ?? false
  }
  var isApp: Bool {
    return self as? Page<AppMetadata> != nil
  }
  var tags: [String] {
    return (self as? Page<ArticleMetadata>)?.metadata.tags ?? []
  }
}

let pageProcessorDateFormatter = DateFormatter()
pageProcessorDateFormatter.dateFormat = "yyyy-MM-dd"
pageProcessorDateFormatter.timeZone = .current

// An example of a simple page processor that takes files such as "2021-01-27-post-with-date-in-filename"
// and uses the date within the filename as the publication date.
func pageProcessor<M: Metadata>(page: Page<M>) {
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
//  .modifyPages()
  .write(
    templates: "templates",
    writers: [
      // Articles
      .section(prefix: "articles", filter: \.isPublicArticle, writers: [
        .pageWriter(template: "article.html"),
        .listWriter(template: "articles.html"),
        .tagWriter(template: "tag.html", tags: \.tags),
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

      // Apps don't get their own individual webpage, instead they are only written using the listWriter
      .listWriter(template: "apps.html", output: "apps/index.html", filter: \.isApp),

      // Other pages
      // We specifically filter on EmptyMetadata here, otherwise it might process articles or apps that were not written by the writers above.
      // For example, there is one article that is not public, so it wouldn't have been written by that first pageWriter. That means all of a
      // sudden this "less specific" pageWriter would now still write that article to disk, which is not what we want.
      // Same for the apps: we don't want to write those as individual pages, so if we don't exclude those, we'd still get them written
      // to disk after all.
      .pageWriter(template: "page.html", filter: { $0 is Page<EmptyMetadata> }),

      // All pages to the sitemap
      // We need to exclude the apps, since those are not "real" pages, see comments above.
      .listWriter(template: "sitemap.xml", output: "sitemap.xml", filter: { !$0.isApp }),
    ]
  )
  // All the remaining files that were not parsed to markdown, so for example images, raw html files and css,
  // are copied as-is to the output folder.
  .staticFiles()
  // Create Twitter preview images for all articles. This only works if you have Python installed with the Pillow dependency.
  .createArticleImages()


extension Saga {
  @discardableResult
  func modifyPages() -> Self {
    let pages = fileStorage.compactMap(\.page)
    for page in pages {
      page.title.append("!")
    }

    return self
  }

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
