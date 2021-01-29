import Foundation
import PathKit

public protocol Metadata: Decodable {}

public struct EmptyMetadata: Metadata {}

public class Page {
  public var relativeSource: Path
  public var relativeDestination: Path
  public var title: String
  public var rawContent: String
  public var body: String
  public var date: Date
  public var metadata: Metadata
  internal var written = false

  internal init(relativeSource: Path, relativeDestination: Path, title: String, rawContent: String, body: String, date: Date, metadata: Metadata, written: Bool = false) {
    self.relativeSource = relativeSource
    self.relativeDestination = relativeDestination
    self.title = title
    self.rawContent = rawContent
    self.body = body
    self.date = date
    self.metadata = metadata
    self.written = written
  }
}
