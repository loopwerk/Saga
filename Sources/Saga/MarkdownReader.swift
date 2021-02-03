import Foundation
import Ink
import Splash
import Codextended
import PathKit
import Slugify

public extension Reader {
  static func markdownReader(pageProcessor: ((Page<M>) -> Void)? = nil) -> Self {
    Reader(supportedExtensions: ["md", "markdown"], convert: { path, relativePath in
      let contents: String = try path.read()

      // First we parse the markdown file, and use the Splash syntax highlighter
      var markdownParser = MarkdownParser()
      markdownParser.addModifier(.splashCodeBlocks())
      let markdown = markdownParser.parse(contents)

      // Then we try to decode the embedded metadata within the markdown (which otherwise is just a [String: String] dict)
      let decoder = makeMetadataDecoder(for: markdown)
      let date = try resolvePublishingDate(from: path, decoder: decoder)
      let metadata = try M.init(from: decoder)
      let template = try decoder.decodeIfPresent("template", as: String.self)

      // Create the Page
      let page = Page(
        relativeSource: relativePath,
        relativeDestination: relativePath.makeOutputPath(),
        title: markdown.title ?? path.lastComponentWithoutExtension,
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

public extension Modifier {
  static func splashCodeBlocks(withFormat format: HTMLOutputFormat = .init()) -> Self {
    let highlighter = SyntaxHighlighter(format: format)

    return Modifier(target: .codeBlocks) { html, markdown in
      var markdown = markdown.dropFirst("```".count)

      guard !markdown.hasPrefix("no-highlight") else {
        return html
      }

      markdown = markdown
        .drop(while: { !$0.isNewline })
        .dropFirst()
        .dropLast("\n```".count)

      let highlighted = highlighter.highlight(String(markdown))
      return "<pre><code>" + highlighted + "\n</code></pre>"
    }
  }
}
