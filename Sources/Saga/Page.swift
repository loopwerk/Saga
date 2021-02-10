import Foundation
import PathKit
import HTML

public protocol Metadata: Codable {}

public struct EmptyMetadata: Metadata {}

public protocol AnyPage: class {
  var relativeSource: Path { get }
  var filenameWithoutExtension: String { get }
  var relativeDestination: Path { get set }
  var title: String { get set }
  var rawContent: String { get set }
  var body: Node { get set }
  var date: Date { get set }
  var lastModified: Date { get set }
  var url: String { get }
}

public class Page<M: Metadata>: AnyPage {
  public let relativeSource: Path
  public var relativeDestination: Path
  public var title: String
  public var rawContent: String
  public var body: Node
  public var date: Date
  public var lastModified: Date
  public var metadata: M

  public init(relativeSource: Path, relativeDestination: Path, title: String, rawContent: String, body: Node, date: Date, lastModified: Date, metadata: M) {
    self.relativeSource = relativeSource
    self.relativeDestination = relativeDestination
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
    var url = "/" + relativeDestination.string
    if url.hasSuffix("/index.html") {
      url.removeLast(10)
    }
    return url
  }
}
