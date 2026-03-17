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
  var body: String { get set }
  var date: Date { get set }
  var created: Date { get }
  var lastModified: Date { get }
  var url: String { get }
  var locale: String? { get set }
  var translations: [String: AnyItem] { get set }
  var children: [AnyItem] { get set }
  var parent: AnyItem? { get set }
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

  /// The title of the item.
  public var title: String

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

  /// The locale of this item, set automatically when i18n is configured.
  public var locale: String? = nil

  /// Translations of this item in other locales, keyed by locale string.
  /// Populated automatically after all items are read when i18n is configured.
  public var translations: [String: AnyItem] = [:]

  /// Typed accessor for a translation in a specific locale.
  public func translation(for locale: String) -> Item<M>? {
    translations[locale] as? Item<M>
  }

  /// Type-erased children. Populated automatically by nested registrations.
  public var children: [AnyItem] = []

  /// Type-erased parent. Populated automatically by nested registrations.
  public var parent: AnyItem? = nil

  /// Typed accessor for children.
  public func children<C: Metadata>(as type: C.Type) -> [Item<C>] {
    children.compactMap { $0 as? Item<C> }
  }

  /// Typed accessor for parent.
  public func parent<P: Metadata>(as type: P.Type) -> Item<P> {
    parent as! Item<P>
  }

  public init(absoluteSource: Path, relativeSource: Path, relativeDestination: Path, title: String, body: String, date: Date, created: Date, lastModified: Date, metadata: M) {
    self.absoluteSource = absoluteSource
    self.relativeSource = relativeSource
    self.relativeDestination = relativeDestination
    self.title = title
    self.body = body
    self.date = date
    self.created = created
    self.lastModified = lastModified
    self.metadata = metadata
  }

  /// Create an Item programmatically (without reading from a file).
  ///
  /// - Parameters:
  ///   - title: The title of the item.
  ///   - body: The body content. Defaults to an empty string.
  ///   - date: The date of the item. Defaults to the current date.
  ///   - relativeDestination: The output path relative to the site's output folder. Defaults to `title-slug/index.html`.
  ///   - metadata: The parsed metadata.
  public convenience init(title: String, body: String = "", date: Date = Date(), relativeDestination: Path? = nil, metadata: M) {
    self.init(
      absoluteSource: Path(""),
      relativeSource: Path(""),
      relativeDestination: relativeDestination ?? Path("\(title.slugified)/index.html"),
      title: title,
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
    case absoluteSource, relativeSource, relativeDestination, title, body, date, created, lastModified, metadata, locale
  }
}
