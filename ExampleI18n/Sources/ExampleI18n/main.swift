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
  .i18n(
    locales: ["en", "nl"],
    defaultLocale: "en",
    localizedOutputFolders: [
      "articles": ["nl": "artikelen"],
      "projects": ["nl": "projecten"],
    ]
  )

  // Articles with list and tag pages
  .register(
    folder: "articles",
    metadata: ArticleMetadata.self,
    readers: [.parsleyMarkdownReader],
    writers: [
      .itemWriter(swim(renderArticle)),
      .listWriter(swim(renderArticles)),
      .tagWriter(swim(renderTag), tags: \.metadata.tags),
    ]
  )

  // Projects, each in its own folder. The screenshots next to each index.md
  // become that project's resources, which the list page shows.
  .register(
    folder: "projects",
    metadata: EmptyMetadata.self,
    readers: [.parsleyMarkdownReader],
    writers: [.listWriter(swim(renderProjects))]
  )

  // All remaining markdown files (about, etc.)
  .register(
    metadata: EmptyMetadata.self,
    readers: [.parsleyMarkdownReader],
    writers: [.itemWriter(swim(renderPage))]
  )

  // Homepage — runs once per locale, allItems is filtered automatically
  .createPage("index.html", forEachLocale: swim(renderHome))

  // Sitemap
  .createPage("sitemap.xml", using: Saga.sitemap(baseURL: SiteMetadata.url))

  .run()
