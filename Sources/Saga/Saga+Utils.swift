import Foundation
import SagaPathKit

/// Run multiple item processors in sequence.
///
/// ```swift
/// .register(
///   metadata: EmptyMetadata.self,
///   readers: [.parsleyMarkdownReader],
///   itemProcessor: sequence(publicationDateInFilename, addExclamationPointToTitle),
///   writers: [.itemWriter(swim(renderPage))]
/// )
/// ```
@preconcurrency
public func sequence<M>(_ processors: (@Sendable (Item<M>) async -> Void)...) -> @Sendable (Item<M>) async -> Void {
  return { item in
    for processor in processors {
      await processor(item)
    }
  }
}

private let publicationDateFormatter: DateFormatter = {
  let pageProcessorDateFormatter = DateFormatter()
  pageProcessorDateFormatter.dateFormat = "yyyy-MM-dd"
  pageProcessorDateFormatter.timeZone = .current
  return pageProcessorDateFormatter
}()

/// An item processor that takes files such as "2021-01-27-post-with-date-in-filename"
/// and uses the date within the filename as the publication date.
@Sendable public func publicationDateInFilename<M>(item: Item<M>) async {
  // If the filename starts with a valid date, use that as the Page's date and strip it from the destination path
  let first10 = String(item.filenameWithoutExtension.prefix(10))
  guard first10.count == 10, let date = publicationDateFormatter.date(from: first10) else {
    return
  }

  // Set the date
  item.date = date

  // And remove the first 11 characters from the filename
  let first11 = String(item.filenameWithoutExtension.prefix(11))
  item.relativeDestination = Path(
    item.relativeSource.string.replacingOccurrences(of: first11, with: "")
  ).makeOutputPath(itemWriteMode: .moveToSubfolder)
}

public extension Saga {
  /// This is `true` when the `SAGA_DEV` environment variable is set (which `saga dev` does
  /// automatically). Use it to skip expensive work during development:
  /// 
  /// ```swift
  /// .postProcess { html, _ in
  ///   Saga.isDev ? html : minifyHTML(html)
  /// }
  /// ```
  static var isDev: Bool {
    ProcessInfo.processInfo.environment["SAGA_DEV"] != nil
  }

  /// This is `true` when the `SAGA_CLI` environment variable is set (which `saga dev` does
  /// automatically). Used internally.
  static var isCLI: Bool {
    ProcessInfo.processInfo.environment["SAGA_CLI"] != nil
  }

  /// A renderer which creates an HTML page that redirects the browser to the given URL.
  ///
  /// Uses both a `<meta http-equiv="refresh">` tag and a canonical link for
  /// immediate client-side redirection with proper SEO signaling.
  ///
  /// - Parameter url: The destination URL to redirect to.
  /// - Returns: A renderer for use with ``StepBuilder/createPage(_:using:)``.
  ///
  /// ```swift
  /// .createPage("old-path/index.html", using: Saga.redirectHTML(to: "/new-path/"))
  /// ```
  @preconcurrency
  static func redirectHTML(to url: String) -> @Sendable (PageRenderingContext) -> String {
    let html = redirectHTML(to: url) as String
    return { _ in html }
  }

  /// Returns an HTML page that redirects the browser to the given URL.
  ///
  /// Uses both a `<meta http-equiv="refresh">` tag and a canonical link for
  /// immediate client-side redirection with proper SEO signaling.
  ///
  /// - Parameter url: The destination URL to redirect to.
  /// - Returns: A complete HTML document that redirects to the given URL.
  static func redirectHTML(to url: String) -> String {
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta http-equiv="refresh" content="0; url=\(url)">
      <link rel="canonical" href="\(url)">
    </head>
    <body>
      <p>Redirecting to <a href="\(url)">\(url)</a></p>
    </body>
    </html>
    """
  }
}
