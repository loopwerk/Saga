import PathKit

/// Readers are responsible for turning text files into ``Item`` instances.
///
/// Every `Reader` can declare what kind of text files it supports, for example Markdown or RestructuredText. Readers are expected to support the parsing of ``Metadata`` contained within a document, such as this example article written in Markdown:
///
/// ```text
/// ---
/// tags: article, news
/// summary: This is the summary
/// ---
/// # Hello world
/// Hello there.
/// ```
///
/// ```swift
/// public extension Reader {
///   static func myMarkdownReader(itemProcessor: ((Item<M>) async -> Void)? = nil) -> Self {
///     Reader(supportedExtensions: ["md", "markdown"], convert: { absoluteSource, relativeSource, relativeDestination in
///       let content: String = try absoluteSource.read()
///
///       // Somehow turn `content` into an ``Item``, and return it:
///       let item = Item(
///         relativeSource: ...,
///         relativeDestination: ...,
///         title: ...,
///         rawContent: ...,
///         body: ...,
///         date: ...,
///         lastModified: ...,
///         metadata: ...
///       )
///
///       return item
///     })
///   }
/// }
/// ```
///
/// > Note: Instead of constructing your own `Reader` from scratch for your website, you should probably install one such as [SagaParsleyMarkdownReader](https://github.com/loopwerk/SagaParsleyMarkdownReader), [SagaPythonMarkdownReader](https://github.com/loopwerk/SagaPythonMarkdownReader), or [SagaInkMarkdownReader](https://github.com/loopwerk/SagaInkMarkdownReader).
public struct Reader<M: Metadata> {
  /// Which file extensions can be handled by this reader? For example `md` or `rst`.
  var supportedExtensions: [String]

  public typealias Converter = (_ absoluteSource: Path, _ relativeSource: Path, _ relativeDestination: Path) async throws -> Item<M>

  /// The function that will do the actual work of reading and converting a file path into an ``Item``.
  var convert: Converter

  /// Initialize a new Reader
  public init(supportedExtensions: [String], convert: @escaping Converter) {
    self.supportedExtensions = supportedExtensions
    self.convert = convert
  }
}
