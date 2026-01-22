import Foundation
import PathKit

public protocol Metadata: Decodable {}

/// A convenience version of ``Metadata`` that's just empty. This can be used, for example, when you don't have custom item metadata.
public struct EmptyMetadata: Metadata {
  public init() {}
}

/// A type-erased version of ``Item``.
public protocol AnyItem: AnyObject {
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
}

/// A model reprenting an item.
///
/// An item can be any text file (like a Markdown or RestructedText file). ``Reader``s will turn the file into an ``Item``, and ``Writer``s will turn the ``Item`` into a `String` (for example HTML or RSS) to be written to disk.
public class Item<M: Metadata>: AnyItem {
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
  /// Pleaae note that the creation date value can be inconsistent when cloning or pulling from git, see https://github.com/loopwerk/Saga/issues/21.
  public var date: Date

  /// The creation date of the item.
  /// Pleaae note that this value can be inconsistent when cloning or pulling from git, see https://github.com/loopwerk/Saga/issues/21.
  public let created: Date

  /// The last modified date of the item.
  /// Pleaae note that this value can be inconsistent when cloning or pulling from git, see https://github.com/loopwerk/Saga/issues/21.
  public let lastModified: Date

  /// The parsed metadata. ``Metadata`` can be any `Codable` object.
  public var metadata: M

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

  public var filenameWithoutExtension: String {
    relativeSource.lastComponentWithoutExtension
  }

  public var url: String {
    relativeDestination.url
  }
}
