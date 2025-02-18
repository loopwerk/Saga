import Foundation

/// A rendered which creates an Atom feed for Items
///
/// - Parameters:
///   - title: The title of the feed, usually your site title. Example: Loopwerk.io.
///   - author: The author of the articles.
///   - baseURL: The base URL of your website, for example https://www.loopwerk.io.
///   - summary: An optional function which takes an `Item` and returns its summary.
/// - Returns: A function which takes a rendering context, and returns a string.
public func atomFeed<Context: AtomContext, M>(title: String, author: String? = nil, baseURL: URL, summary: ((Item<M>) -> String?)? = nil) -> (_ context: Context) -> String where Context.M == M {
  let RFC3339_DF = ISO8601DateFormatter()

  return { context in
    let feedPath = context.outputPath.string
    let currentDate = RFC3339_DF.string(from: Date())

    // Build the feed header
    var xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
        <id>\(baseURL.appendingPathComponent(feedPath).absoluteString)</id>
        <title>\(escapeXML(title))</title>

    """

    // Add optional author
    if let author = author {
      xml += """
          <author>
              <name>\(escapeXML(author))</name>
          </author>

      """
    }

    // Add link and updated date
    xml += """
        <link rel="self" href="\(baseURL.absoluteString)"/>
        <updated>\(currentDate)</updated>

    """

    // Add entries
    for item in context.items {
      let itemURL = baseURL.appendingPathComponent(item.url).absoluteString

      xml += """
          <entry>
              <id>\(itemURL)</id>
              <title>\(escapeXML(item.title))</title>
              <updated>\(RFC3339_DF.string(from: item.lastModified))</updated>

      """

      if let summary, let summaryString = summary(item) {
        xml += """
            <summary>\(escapeXML(summaryString))</summary>
            <link rel="alternate" href="\(itemURL)"/>

        """
      } else {
        xml += """
            <content type="html">\(escapeXML(item.body))</content>

        """
      }

      xml += "    </entry>\n"
    }

    // Close the feed
    xml += "</feed>"

    return xml
  }
}

// Helper function to escape special XML characters
private func escapeXML(_ string: String) -> String {
  return string
    .replacingOccurrences(of: "&", with: "&amp;")
    .replacingOccurrences(of: "<", with: "&lt;")
    .replacingOccurrences(of: ">", with: "&gt;")
    .replacingOccurrences(of: "\"", with: "&quot;")
    .replacingOccurrences(of: "'", with: "&apos;")
}
