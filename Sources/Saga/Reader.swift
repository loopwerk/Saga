import PathKit

public struct Reader<M: Metadata> {
  var supportedExtensions: [String]
  var convert: (Path, Path) throws -> Page<M>

  public init(supportedExtensions: [String], convert: @escaping (Path, Path) throws -> Page<M>) {
    self.supportedExtensions = supportedExtensions
    self.convert = convert
  }
}
