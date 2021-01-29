import PathKit

public struct Reader {
  var supportedExtensions: [String]
  var convert: (Path, Metadata.Type, Path) throws -> Page
}
