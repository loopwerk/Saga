import PathKit

public struct FileIO {
  var resolveSwiftPackageFolder: (Path) throws -> Path
  var findFiles: (Path) throws -> [Path]
  var deletePath: (Path) throws -> Void
  var write: (Path, String) throws -> Void
}

public extension FileIO {
  static var live = Self(
    resolveSwiftPackageFolder: { path in try path.resolveSwiftPackageFolder() },
    findFiles: { try $0.recursiveChildren().filter(\.isFile) },
    deletePath: { path in
      if path.exists {
        try path.delete()
      }
    },
    write: { destination, content in
      try destination.parent().mkpath()
      try destination.write(content)
    }
  )
}
