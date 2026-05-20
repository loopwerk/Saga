import Foundation
import SagaPathKit

#if compiler(>=6.2)
  public protocol Metadata: Codable, SendableMetatype {}
#else
  public protocol Metadata: Codable {}
#endif

/// A convenience version of ``Metadata`` that's just empty. This can be used, for example, when you don't have custom item metadata.
public struct EmptyMetadata: Metadata {
  public init() {}
}

/// A type-erased version of ``Item``.
public protocol AnyItem: AnyObject, Sendable {
  var absoluteSource: Path { get }
  var relativeSource: Path { get }
  var filenameWithoutExtension: String { get }
  var relativeDestination: Path { get set }
  var title: String { get set }
  var seoTitle: String { get set }
  var body: String { get set }
  var date: Date { get set }
  var created: Date { get }
  var lastModified: Date { get }
  var url: String { get }
  var children: [AnyItem] { get set }
  var parent: AnyItem? { get set }
  var locale: SagaLocale? { get set }
  var translations: [SagaLocale: AnyItem] { get set }
}

/// A model representing an item.
///
/// An item can be any text file (like a Markdown or RestructedText file). ``Reader``s will turn the file into an ``Item``, and ``Writer``s will turn the ``Item`` into a `String` (for example HTML or RSS) to be written to disk.
public class Item<M: Metadata>: AnyItem, Codable, @unchecked Sendable {
  /// The absolute path of the file
  public let absoluteSource: Path

  /// The path of the file, relative to the site's `input`.
  public let relativeSource: Path

  /// The destination, where the ``Writer`` will write it to disk.
  public var relativeDestination: Path

  /// The display title of the item, intended for use as the visible `<h1>` on the page.
  ///
  /// Priority: `# ` heading in the markdown body → `title:` front matter → filename.
  ///
  /// If the markdown body begins with a `# ` heading, that heading is extracted by the
  /// reader and given the highest priority here. This lets authors write a rich, human-
  /// friendly headline in Markdown while using `title:` purely for SEO purposes.
  public var title: String

  /// The SEO title of the item, intended for use in the HTML `<title>` tag and meta tags.
  ///
  /// Priority: `title:` front matter → `# ` heading in the markdown body → filename.
  ///
  /// This is the mirror of ``title``: it gives the explicit front-matter `title:` key the
  /// highest priority so authors can craft a keyword-optimised page title that differs from
  /// the human-readable `<h1>`. Both properties always resolve to a non-empty string.
  public var seoTitle: String

  /// The body of the file, without the metadata header, and without the first title.
  public var body: String

  /// The date of the item. Will be taken from the metadata if available, defaults to the creation date otherwise.
  /// Please note that the creation date value can be inconsistent when cloning or pulling from git, see https://github.com/loopwerk/Saga/issues/21.
  public var date: Date

  /// The creation date of the item.
  /// Please note that this value can be inconsistent when cloning or pulling from git, see https://github.com/loopwerk/Saga/issues/21.
  public let created: Date

  /// The last modified date of the item.
  /// Please note that this value can be inconsistent when cloning or pulling from git, see https://github.com/loopwerk/Saga/issues/21.
  public let lastModified: Date

  /// The parsed metadata. ``Metadata`` can be any `Codable` object.
  public var metadata: M

  /// The locale of this item, or `nil` when i18n is not configured.
  public var locale: SagaLocale? = nil

  /// Other language versions of this item, keyed by locale.
  public var translations: [SagaLocale: AnyItem] = [:]

  /// Type-erased children. Populated automatically by nested registrations.
  public var children: [AnyItem] = []

  /// Type-erased parent. Populated automatically by nested registrations.
  public weak var parent: AnyItem? = nil

  /// Typed accessor for children.
  public func children<C: Metadata>(as type: C.Type) -> [Item<C>] {
    children.compactMap { $0 as? Item<C> }
  }

  /// Typed accessor for parent.
  public func parent<P: Metadata>(as type: P.Type) -> Item<P> {
    parent as! Item<P>
  }

  /// Returns the translation for the given locale, if available.
  public func translation(for locale: SagaLocale) -> Item<M>? {
    translations[locale] as? Item<M>
  }

  public init(absoluteSource: Path, relativeSource: Path, relativeDestination: Path, title: String, seoTitle: String, body: String, date: Date, created: Date, lastModified: Date, metadata: M) {
    self.absoluteSource = absoluteSource
    self.relativeSource = relativeSource
    self.relativeDestination = relativeDestination
    self.title = title
    self.seoTitle = seoTitle
    self.body = body
    self.date = date
    self.created = created
    self.lastModified = lastModified
    self.metadata = metadata
  }

  /// Create an Item programmatically (without reading from a file).
  ///
  /// - Parameters:
  ///   - title: The display title of the item (used for `<h1>`).
  ///   - seoTitle: The SEO title for the HTML `<title>` tag. Defaults to `title` when not provided.
  ///   - body: The body content. Defaults to an empty string.
  ///   - date: The date of the item. Defaults to the current date.
  ///   - relativeDestination: The output path relative to the site's output folder. Defaults to `title-slug/index.html`.
  ///   - metadata: The parsed metadata.
  public convenience init(title: String, seoTitle: String? = nil, body: String = "", date: Date = Date(), relativeDestination: Path? = nil, metadata: M) {
    self.init(
      absoluteSource: Path(""),
      relativeSource: Path(""),
      relativeDestination: relativeDestination ?? Path("\(title.slugified)/index.html"),
      title: title,
      seoTitle: seoTitle ?? title,
      body: body,
      date: date,
      created: date,
      lastModified: date,
      metadata: metadata
    )
  }

  public var filenameWithoutExtension: String {
    relativeSource.lastComponentWithoutExtension
  }

  public var url: String {
    relativeDestination.url
  }

  enum CodingKeys: String, CodingKey {
    case absoluteSource, relativeSource, relativeDestination, title, seoTitle, body, date, created, lastModified, metadata
  }
}
