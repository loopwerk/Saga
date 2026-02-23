import PathKit

/// A wrapper around a `Path`, used to keep track if got handled by one of the registered processing steps.
public class FileContainer {
  public let path: Path
  public let relativePath: Path

  @available(*, deprecated, message: "Use saga.allItems instead")
  public internal(set) var item: AnyItem? {
    get { _item }
    set { _item = newValue }
  }
  var _item: AnyItem?

  public var handled: Bool

  init(path: Path, relativePath: Path) {
    self.path = path
    self.relativePath = relativePath
    _item = nil
    handled = false
  }
}
