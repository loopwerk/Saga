import SagaPathKit

/// A wrapper around a `Path`, used to keep track if got handled by one of the registered processing steps.
public class FileContainer: @unchecked Sendable {
  public let path: Path
  public let relativePath: Path
  public var handled: Bool
  var contentHash: String?

  init(path: Path, relativePath: Path) {
    self.path = path
    self.relativePath = relativePath
    handled = false
    contentHash = nil
  }
}
