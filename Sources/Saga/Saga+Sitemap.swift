import Foundation
import SagaPathKit

@available(*, deprecated, message: "Use Saga.sitemap() instead")
public func sitemap(baseURL: URL, filter: (@Sendable (Path) -> Bool)? = nil) -> @Sendable (PageRenderingContext) -> String {
  Saga.sitemap(baseURL: baseURL, filter: filter)
}

public extension Saga {
  /// A renderer which creates an XML sitemap from all generated pages.
  ///
  /// When i18n is configured, the sitemap includes `xhtml:link` alternate entries
  /// for pages that have translations in other locales, following Google's
  /// [multilingual sitemap](https://developers.google.com/search/docs/specialty/international/localized-versions#sitemap)
  /// specification.
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
      // Filter out the sitemap itself, and apply user filter
      var groups = context.generatedPages.map { group in
        group.filter { _, path in
          path != context.outputPath && (filter?(path) ?? true)
        }
      }
      .filter { !$0.isEmpty }

      // Sort by smallest path in each group
      groups.sort { a, b in
        let aPath = a.values.min(by: { $0.string < $1.string })?.string ?? ""
        let bPath = b.values.min(by: { $0.string < $1.string })?.string ?? ""
        return aPath < bPath
      }

      let needsXmlns = groups.contains { $0.count > 1 }
      var xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"\(needsXmlns ? "\n       xmlns:xhtml=\"http://www.w3.org/1999/xhtml\"" : "")>

      """

      for group in groups {
        let sortedEntries = group.sorted { $0.key < $1.key }

        for (_, path) in sortedEntries {
          xml += "  <url>\n"
          xml += "    <loc>\(base)\(path.url)</loc>\n"
          if group.count > 1 {
            for (locale, altPath) in sortedEntries {
              xml += "    <xhtml:link rel=\"alternate\" hreflang=\"\(locale)\" href=\"\(base)\(altPath.url)\"/>\n"
            }
          }
          xml += "  </url>\n"
        }
      }

      xml += "</urlset>"
      return xml
    }
  }
}
