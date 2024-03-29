import PathKit

/// A wrapper around a `Path`, used to keep track if got handled by one of the registered processing steps.
public class FileContainer {
  public let path: Path
  public internal(set) var item: AnyItem?
  public var handled: Bool

  internal init(path: Path) {
    self.path = path
    self.item = nil
    self.handled = false
  }
}
