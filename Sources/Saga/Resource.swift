import SagaPathKit

/// A file that no reader handled, such as an image, which Saga copies as-is to the output folder.
public struct Resource: Sendable {
  /// The absolute path of the file.
  public let absoluteSource: Path

  /// The path of the file, relative to the site's `input`.
  public let relativeSource: Path

  /// The path the file is copied to, relative to the site's `output`.
  public let relativeDestination: Path

  public var filenameWithoutExtension: String {
    relativeSource.lastComponentWithoutExtension
  }

  public var url: String {
    relativeDestination.url
  }
}
