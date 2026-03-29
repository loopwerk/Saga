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
  ///   - filter: An optional filter to exclude certain paths from the sitemap.
  ///     The filter receives the relative output path (e.g. `"404.html"` or `"search/index.html"`).
  ///     Return `true` to include the path, `false` to exclude it.
  /// - Returns: A renderer for use with ``StepBuilder/createPage(_:using:)``. Place the sitemap as the last `createPage` call so it can see all generated pages before it.
  ///
  /// ```swift
  /// .createPage("sitemap.xml", using: sitemap(
  ///   baseURL: URL(string: "https://www.example.com")!,
  ///   filter: { $0 != "404.html" }
  /// ))
  /// ```
  @preconcurrency
  static func sitemap(baseURL: URL, filter: (@Sendable (Path) -> Bool)? = nil) -> @Sendable (PageRenderingContext) -> String {
    let absString = baseURL.absoluteString
    let base = absString.hasSuffix("/") ? String(absString.dropLast()) : absString

    return { context in
      var paths = context.generatedPages.filter { $0 != context.outputPath }
      if let filter {
        paths = paths.filter(filter)
      }

      paths.sort { $0.string < $1.string }

      // Build a lookup from destination path → item for alternate links
      let pathSet = Set(paths.map(\.string))
      let itemByDest = context.allItems
        .filter { $0.locale != nil && pathSet.contains($0.relativeDestination.string) }
        .reduce(into: [String: AnyItem]()) { into, item in
          into[item.relativeDestination.string] = item
        }

      let hasAlternates = !itemByDest.isEmpty
      var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
      xml += "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\""
      if hasAlternates {
        xml += "\n xmlns:xhtml=\"http://www.w3.org/1999/xhtml\""
      }
      xml += ">\n"

      for path in paths {
        xml += "<url>\n"
        xml += "<loc>\(base)\(path.url)</loc>\n"

        if let item = itemByDest[path.string], let locale = item.locale, !item.translations.isEmpty {
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
