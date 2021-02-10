import Foundation
import Parsley
import Codextended
import PathKit

public extension Reader {
  static func markdownReader(pageProcessor: ((Page<M>) -> Void)? = nil) -> Self {
    Reader(supportedExtensions: ["md", "markdown"], convert: { absoluteSource, relativeSource, relativeDestination in
      let contents: String = try absoluteSource.read()

      // First we parse the markdown file
      let markdown = try Parsley.parse(contents, options: [.safe, .hardBreaks, .smartQuotes])

      // Then we try to decode the embedded metadata within the markdown (which otherwise is just a [String: String] dict)
      let decoder = makeMetadataDecoder(for: markdown.metadata)
      let date = try resolvePublishingDate(from: absoluteSource, decoder: decoder)
      let metadata = try M.init(from: decoder)

      // Create the Page
      let page = Page(
        relativeSource: relativeSource,
        relativeDestination: relativeDestination,
        title: markdown.title ?? absoluteSource.lastComponentWithoutExtension,
        rawContent: contents,
        body: markdown.body.asNode(),
        date: date,
        lastModified: absoluteSource.modificationDate ?? Date(),
        metadata: metadata
      )

      // Run the processor, if any, to modify the Page
      if let pageProcessor = pageProcessor {
        pageProcessor(page)
      }

      return page
    })
  }
}
