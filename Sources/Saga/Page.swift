import Foundation
import PathKit

public protocol Metadata: Decodable {}

public struct EmptyMetadata: Metadata {}

public protocol AnyPage: class {
  var relativeSource: Path { get }
  var filenameWithoutExtension: String { get }
  var relativeDestination: Path { get set } /// if empty, it'll be calculated by the pageWriter
  var title: String { get set }
  var rawContent: String { get set }
  var body: String { get set }
  var date: Date { get set }
  var lastModified: Date { get set }
  var template: Path? { get set }

  // This is only used in the templates, to be able to do this:
  // {% for page in allPages where page.metadataType == "ArticleMetadata" %}
  // This should definitely be removed once Stencil has been replaced with a strongly typed HTML DSL library.
  var metadataType: String { get }
}

public class Page<M: Metadata>: AnyPage {
  public let relativeSource: Path
  public let filenameWithoutExtension: String
  public var relativeDestination: Path
  public var title: String
  public var rawContent: String
  public var body: String
  public var date: Date
  public var lastModified: Date
  public var metadata: M
  public var metadataType: String // Remove once Stencil has been replaced
  public var template: Path?

  public init(relativeSource: Path, relativeDestination: Path, title: String, rawContent: String, body: String, date: Date, lastModified: Date, metadata: M, template: Path? = nil) {
    self.relativeSource = relativeSource
    self.relativeDestination = relativeDestination
    self.filenameWithoutExtension = relativeSource.lastComponentWithoutExtension
    self.relativeDestination = relativeDestination
    self.title = title
    self.rawContent = rawContent
    self.body = body
    self.date = date
    self.lastModified = lastModified
    self.metadata = metadata
    self.metadataType = String(String(describing: metadata).split(separator: "(").first!)
    self.template = template
  }
}
