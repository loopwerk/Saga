import Foundation
import Saga
import SagaParsleyMarkdownReader
import SagaPathKit
import SagaSwimRenderer

enum SiteMetadata {
  static let url = URL(string: "http://www.example.com")!
  static let name = "i18n Example"
  static let author = "Kevin Renskers"
}

struct ArticleMetadata: Metadata {
  let tags: [String]
}

try await Saga(input: "content", output: "deploy")
  .i18n(locales: ["en", "nl"], defaultLocale: "en")

  // Articles with list and tag pages
  // Dutch uses "artikelen" instead of "articles" in the URL
  .register(
    folder: "articles",
    localizedOutputFolder: ["nl": "artikelen"],
    metadata: ArticleMetadata.self,
    readers: [.parsleyMarkdownReader],
    writers: [
      .itemWriter(swim(renderArticle)),
      .listWriter(swim(renderArticles)),
      .tagWriter(swim(renderTag), tags: \.metadata.tags),
    ]
  )

  // All remaining markdown files (index, about)
  .register(
    metadata: EmptyMetadata.self,
    readers: [.parsleyMarkdownReader],
    writers: [.itemWriter(swim(renderPage))]
  )

  // Sitemap
  .createPage("sitemap.xml", using: Saga.sitemap(baseURL: SiteMetadata.url))

  .run()
