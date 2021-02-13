import PathKit

public struct Reader<M: Metadata> {
  var supportedExtensions: [String]

  /// Parameters: absoluteSource, relativeSource, relativeDestination
  var convert: (Path, Path, Path) throws -> Item<M>

  public init(supportedExtensions: [String], convert: @escaping (Path, Path, Path) throws -> Item<M>) {
    self.supportedExtensions = supportedExtensions
    self.convert = convert
  }
}
