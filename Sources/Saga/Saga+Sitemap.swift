import Foundation
import SagaPathKit

public extension Saga {
  /// A renderer which creates an XML sitemap from all generated pages.
  ///
  /// When i18n is configured, the sitemap includes `xhtml:link` alternate entries
  /// for pages that have translations in other locales, following Google's
  /// [multilingual sitemap](https://developers.google.com/search/docs/specialty/international/localized-versions#sitemap)
  /// specification.
  ///
  /// For a complete walkthrough, see <doc:GeneratingSitemaps>.
  ///
  /// - Parameters:
  ///   - baseURL: The base URL of your website, for example `https://www.example.com`.
  /// - Returns: A renderer for use with ``StepBuilder/createPage(_:using:)``. Place the sitemap as the last `createPage` call so it can see all generated pages before it.
  ///
  /// ```swift
  /// .createPage("sitemap.xml", using: sitemap(baseURL: URL(string: "https://www.example.com")!))
  /// ```
  static func sitemap(baseURL: URL) -> @Sendable (PageRenderingContext) -> String {
    sitemap(baseURL: baseURL, filter: { _, _ in true })
  }

  /// A renderer which creates an XML sitemap from all generated pages.
  @available(*, deprecated, message: "Use sitemap(baseURL:filter:) with the item-aware (Path, AnyItem?) -> Bool filter instead")
  @preconcurrency
  static func sitemap(baseURL: URL, filter: (@Sendable (Path) -> Bool)?) -> @Sendable (PageRenderingContext) -> String {
    sitemap(baseURL: baseURL, filter: { path, _ in filter?(path) ?? true })
  }

  /// A renderer which creates an XML sitemap from all generated pages.
  ///
  /// When i18n is configured, the sitemap includes `xhtml:link` alternate entries
  /// for pages that have translations in other locales, following Google's
  /// [multilingual sitemap](https://developers.google.com/search/docs/specialty/international/localized-versions#sitemap)
  /// specification.
  ///
  /// For a complete walkthrough, see <doc:GeneratingSitemaps>.
  ///
  /// - Parameters:
  ///   - baseURL: The base URL of your website, for example `https://www.example.com`.
  ///   - filter: A filter to exclude certain pages from the sitemap. It receives the relative
  ///     output path (e.g. `"articles/hello-world/index.html"`) and the item that produced the
  ///     page, or `nil` for pages without a backing item. Return `true` to include the page,
  ///     `false` to exclude it.
  /// - Returns: A renderer for use with ``StepBuilder/createPage(_:using:)``. Place the sitemap as the last `createPage` call so it can see all generated pages before it.
  ///
  /// ```swift
  /// .createPage("sitemap.xml", using: sitemap(
  ///   baseURL: URL(string: "https://www.example.com")!,
  ///   filter: { _, item in
  ///     guard let article = item as? Item<ArticleMetadata> else { return true }
  ///     return article.metadata.draft != true
  ///   }
  /// ))
  /// ```
  @preconcurrency
  static func sitemap(baseURL: URL, filter: @Sendable @escaping (Path, AnyItem?) -> Bool) -> @Sendable (PageRenderingContext) -> String {
    let absString = baseURL.absoluteString
    let base = absString.hasSuffix("/") ? String(absString.dropLast()) : absString

    return { context in
      let pages = context.generatedPages
        .filter { $0.key != context.outputPath && filter($0.key, $0.value) }
        .sorted { $0.key.string < $1.key.string }

      let pathSet = Set(pages.map(\.key.string))
      let hasAlternates = pages.contains { $0.value?.locale != nil }
      var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
      xml += "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\""
      if hasAlternates {
        xml += "\n xmlns:xhtml=\"http://www.w3.org/1999/xhtml\""
      }
      xml += ">\n"

      for (path, item) in pages {
        xml += "<url>\n"
        xml += "<loc>\(base)\(path.url)</loc>\n"

        if let item, let locale = item.locale, !item.translations.isEmpty {
          // Include self + all translations as alternates
          var alternates = [(locale, path)]
          for (tLocale, tItem) in item.translations {
            if pathSet.contains(tItem.relativeDestination.string) {
              alternates.append((tLocale, tItem.relativeDestination))
            }
          }
          alternates.sort { $0.0 < $1.0 }
          for (altLocale, altPath) in alternates {
            xml += "<xhtml:link rel=\"alternate\" hreflang=\"\(altLocale)\" href=\"\(base)\(altPath.url)\"/>\n"
          }
        }

        xml += "</url>\n"
      }

      xml += "</urlset>"
      return xml
    }
  }
}
