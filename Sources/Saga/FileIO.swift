import Foundation
import PathKit

/// A wrapper around file operations used by Saga, to abstract away the PathKit dependency.
public struct FileIO: Sendable {
  var resolveSwiftPackageFolder: @Sendable (Path) throws -> Path
  var findFiles: @Sendable (Path) throws -> [Path]
  var deletePath: @Sendable (Path) throws -> Void
  var write: @Sendable (Path, String) throws -> Void
  var mkpath: @Sendable (Path) throws -> Void
  var read: @Sendable (Path) throws -> Data
  var copy: @Sendable (Path, Path) throws -> Void
  var creationDate: @Sendable (Path) -> Date?
  var modificationDate: @Sendable (Path) -> Date?
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
    read: { path in
      try path.read()
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
