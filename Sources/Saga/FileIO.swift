import PathKit

public struct FileIO {
  var resolveSwiftPackageFolder: (Path) throws -> Path
  var findFiles: (Path) throws -> [Path]
  var deletePath: (Path) throws -> Void
  var write: (Path, String) throws -> Void
  var mkpath: (Path) throws -> Void
  var copy: (Path, Path) throws -> Void
}

public extension FileIO {
  static var diskAccess = Self(
    resolveSwiftPackageFolder: { path in try path.resolveSwiftPackageFolder() },
    findFiles: { try $0.recursiveChildren().filter { $0.isFile }},
    deletePath: { path in
      if path.exists {
        try path.delete()
      }
    },
    write: { destination, content in
      try destination.parent().mkpath()
      try destination.write(content)
    },
    mkpath: { path in
      try path.mkpath()
    },
    copy: { origin, destination in
      try origin.copy(destination)
    }
  )
}
