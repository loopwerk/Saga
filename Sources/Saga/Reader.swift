import PathKit

public struct Reader<M: Metadata> {
  var supportedExtensions: [String]
  var convert: (Path, Path) throws -> Page<M>
}
