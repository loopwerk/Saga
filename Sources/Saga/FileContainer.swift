import PathKit

internal class FileContainer {
  let path: Path
  var page: Page?
  var handled: Bool

  internal init(path: Path) {
    self.path = path
    self.page = nil
    self.handled = false
  }
}
