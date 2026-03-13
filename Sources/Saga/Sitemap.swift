import Foundation
import SagaPathKit

/// A renderer which creates an XML sitemap from all generated pages.
///
/// - Parameters:
///   - baseURL: The base URL of your website, for example `https://www.example.com`.
///   - filter: An optional filter to exclude certain paths from the sitemap.
///     The filter receives the relative output path (e.g. `"404.html"` or `"search/index.html"`).
///     Return `true` to include the path, `false` to exclude it.
/// - Returns: A function which takes a ``PageRenderingContext`` and returns the sitemap XML as a string.
///
/// ```swift
/// .createPage("sitemap.xml", using: sitemap(
///   baseURL: URL(string: "https://www.example.com")!,
///   filter: { $0 != "404.html" }
/// ))
/// ```
@preconcurrency
public func sitemap(baseURL: URL, filter: (@Sendable (Path) -> Bool)? = nil) -> @Sendable (PageRenderingContext) -> String {
  let absString = baseURL.absoluteString
  let base = absString.hasSuffix("/") ? String(absString.dropLast()) : absString

  return { context in
    var paths = context.generatedPages.filter { $0 != context.outputPath }
    if let filter {
      paths = paths.filter(filter)
    }

    paths.sort { $0.string < $1.string }

    var xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">

    """

    for path in paths {
      xml += """
        <url>
          <loc>\(base)\(path.url)</loc>
        </url>

      """
    }

    xml += "</urlset>"
    return xml
  }
}
