import Foundation
import PathKit

public protocol Metadata: Decodable {}

public struct EmptyMetadata: Metadata {}

public protocol AnyPage: class {
  var relativeSource: Path { get set }
  var relativeDestination: Path { get set }
  var title: String { get set }
  var rawContent: String { get set }
  var body: String { get set }
  var date: Date { get set }
  var lastModified: Date { get set }
  var template: Path? { get set }
}

protocol WritablePage: class {
  var written: Bool { get set }
}

public class Page<M: Metadata>: AnyPage, WritablePage {
  public var relativeSource: Path
  public var relativeDestination: Path
  public var title: String
  public var rawContent: String
  public var body: String
  public var date: Date
  public var lastModified: Date
  public var metadata: M
  public var template: Path?
  internal var written = false

  internal init(relativeSource: Path, relativeDestination: Path, title: String, rawContent: String, body: String, date: Date, lastModified: Date, metadata: M, template: Path? = nil) {
    self.relativeSource = relativeSource
    self.relativeDestination = relativeDestination
    self.title = title
    self.rawContent = rawContent
    self.body = body
    self.date = date
    self.lastModified = lastModified
    self.metadata = metadata
    self.template = template
    self.written = false
  }
}
