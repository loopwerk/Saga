import PathKit

public class FileContainer {
  public let path: Path
  public internal(set) var page: AnyPage?
  public var handled: Bool

  internal init(path: Path) {
    self.path = path
    self.page = nil
    self.handled = false
  }
}
