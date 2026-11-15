import SagaPathKit

/// A file that no reader handled, such as an image, which Saga copies as-is to the output folder.
public struct Resource: Sendable {
  /// The absolute path of the file.
  public let absoluteSource: Path

  /// The path of the file, relative to the site's `input`.
  public let relativeSource: Path

  /// The path the file is copied to, relative to the site's `output`.
  public let relativeDestination: Path

  /// The URL of the file on the site.
  public let url: String

  init(absoluteSource: Path, relativeSource: Path, relativeDestination: Path) {
    self.absoluteSource = absoluteSource
    self.relativeSource = relativeSource
    self.relativeDestination = relativeDestination
    url = relativeDestination.url
  }
}
