import Foundation
import SwiftMarkdown2
import Codextended
import PathKit
import Slugify

public extension Reader {
  static func markdownReader(pageProcessor: ((Page<M>) -> Void)? = nil) -> Self {
    Reader(supportedExtensions: ["md", "markdown"], convert: { path, relativePath in
      let contents: String = try path.read()

      // First we parse the markdown file
      let markdown = try SwiftMarkdown2.markdown(contents, extras: [.breakOnNewline, .cuddledLists, .fencedCodeBlocks, .metadata, .strike, .smartyPants])

      // Then we try to decode the embedded metadata within the markdown (which otherwise is just a [String: String] dict)
      let decoder = makeMetadataDecoder(for: markdown)
      let date = try resolvePublishingDate(from: path, decoder: decoder)
      let metadata = try M.init(from: decoder)
      let template = try decoder.decodeIfPresent("template", as: String.self)

      // Create the Page
      let page = Page(
        relativeSource: relativePath,
        relativeDestination: relativePath.makeOutputPath(),
        title: path.lastComponentWithoutExtension,
        rawContent: contents,
        body: markdown.html,
        date: date,
        lastModified: path.modificationDate ?? Date(),
        metadata: metadata,
        template: template != nil ? Path(template!) : nil
      )

      // Run the processor, if any, to modify the Page
      if let pageProcessor = pageProcessor {
        pageProcessor(page)
      }

      return page
    })
  }
}

private extension Reader {
  static func makeMetadataDecoder(for markdown: Markdown) -> MetadataDecoder {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    dateFormatter.timeZone = .current

    return MetadataDecoder(
      metadata: markdown.metadata,
      dateFormatter: dateFormatter
    )
  }

  static func resolvePublishingDate(from path: Path, decoder: MetadataDecoder) throws -> Date {
    return try decoder.decodeIfPresent("date", as: Date.self) ?? path.modificationDate ?? Date()
  }
}
