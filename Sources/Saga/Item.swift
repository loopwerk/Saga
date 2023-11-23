import Foundation
import PathKit

public protocol Metadata: Decodable {}

/// A convenience version of ``Metadata`` that's just empty. This can be used, for example, when you don't have custom item metadata.
public struct EmptyMetadata: Metadata {
  public init() {}
}

/// A type-erased version of ``Item``.
public protocol AnyItem: AnyObject {
  var relativeSource: Path { get }
  var filenameWithoutExtension: String { get }
  var relativeDestination: Path { get set }
  var title: String { get set }
  var rawContent: String { get set }
  var body: String { get set }
  var date: Date { get set }
  var lastModified: Date { get set }
  var url: String { get }
}

/// A model reprenting an item.
///
/// An item can be any text file (like a Markdown or RestructedText file). ``Reader``s will turn the file into an ``Item``, and ``Writer``s will turn the ``Item`` into a `String` (for example HTML or RSS) to be written to disk.
public class Item<M: Metadata>: AnyItem {
  /// The path of the file, relative to the site's `input`.
  public let relativeSource: Path

  /// The destination, where the ``Writer`` will write it to disk.
  public var relativeDestination: Path

  /// The title of the item.
  public var title: String

  /// The raw contents of the file, not parsed in any way.
  public var rawContent: String

  /// The body of the file, without the metadata header, and without the first title.
  public var body: String

  /// The published date of the item.
  public var date: Date

  /// The last modified date of the item.
  public var lastModified: Date

  /// The parsed metadata. ``Metadata`` can be any `Codable` object.
  public var metadata: M

  public init(relativeSource: Path, relativeDestination: Path, title: String, rawContent: String, body: String, date: Date, lastModified: Date, metadata: M) {
    self.relativeSource = relativeSource
    self.relativeDestination = relativeDestination
    self.title = title
    self.rawContent = rawContent
    self.body = body
    self.date = date
    self.lastModified = lastModified
    self.metadata = metadata
  }

  public var filenameWithoutExtension: String {
    relativeSource.lastComponentWithoutExtension
  }

  public var url: String {
    relativeDestination.url
  }
}
