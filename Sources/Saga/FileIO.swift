import PathKit
import Foundation

/// A wrapper around file operations used by Saga, to abstract away the PathKit dependency.
public struct FileIO {
  var resolveSwiftPackageFolder: (Path) throws -> Path
  var findFiles: (Path) throws -> [Path]
  var deletePath: (Path) throws -> Void
  var write: (Path, String) throws -> Void
  var mkpath: (Path) throws -> Void
  var copy: (Path, Path) throws -> Void
  var creationDate: (Path) -> Date?
  var modificationDate: (Path) -> Date?
}

public extension FileIO {
  /// The default version of `FileIO`, which uses PathKit.
  static var diskAccess = Self(
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
    },
    mkpath: { path in
      try path.mkpath()
    },
    copy: { origin, destination in
      try origin.copy(destination)
    },
    creationDate: { path in
      path.creationDate
    },
    modificationDate: { path in
      path.modificationDate
    }
  )
}
