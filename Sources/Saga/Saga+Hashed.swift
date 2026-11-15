#if canImport(CryptoKit)
  import CryptoKit
#else
  import Crypto
#endif
import Foundation
import SagaPathKit

private nonisolated(unsafe) var _hashFunction: ((String) -> String)?
private let _hashLock = NSLock()

private func setHashFunction(_ fn: ((String) -> String)?) {
  _hashLock.withLock {
    _hashFunction = fn
  }
}

/// Insert the hash into the filename: `static/style.css` becomes `static/style-a1b2c3d4.css`.
private func hashedPath(_ path: Path, hash: String) -> Path {
  let ext = path.extension ?? ""
  return path.parent() + Path(path.lastComponentWithoutExtension + "-" + hash + (ext.isEmpty ? "" : ".\(ext)"))
}

public extension Saga {
  /// Returns a cache-busted file path by inserting a content hash into the filename.
  ///
  /// The path is the file's location in the output folder. With i18n that can differ from its
  /// location in the input folder, for example a resource's `url`.
  ///
  /// ```swift
  /// link(rel: "stylesheet", href: Saga.hashed("/static/output.css"))
  /// // → "/static/output-a1b2c3d4.css"
  /// ```
  static func hashed(_ path: String) -> String {
    _hashLock.withLock {
      _hashFunction?(path) ?? path
    }
  }
}

extension Saga {
  /// Set up the hash function so renderers can call `Saga.hashed()` during the write phase.
  /// In dev mode, hashing is skipped so filenames stay stable for auto-reload.
  func setupHashFunction() {
    guard !Saga.isDev else { return }

    let resourcesByPath = Dictionary(resources.map { ($0.relativeDestination.string, $0) }, uniquingKeysWith: { first, _ in first })
    var warnedPaths: Set<String> = []

    setHashFunction { [weak self] path in
      guard let self else { return path }
      let stripped = path.hasPrefix("/") ? String(path.dropFirst()) : path
      let prefix = path.hasPrefix("/") ? "/" : ""

      if let cached = contentHashes[stripped] {
        return prefix + hashedPath(Path(stripped), hash: cached).string
      }

      guard let resource = resourcesByPath[stripped] else {
        // Every page that links the file calls this, so only warn the first time
        if warnedPaths.insert(stripped).inserted {
          fileIO.log("⚠️ Saga.hashed: no file found at \(path) in the output folder, so it's not hashed")
        }
        return path
      }

      do {
        let data = try fileIO.read(resource.absoluteSource)
        let digest = Insecure.MD5.hash(data: data)
        let hashString = String(digest.map { String(format: "%02x", $0) }.joined().prefix(8))
        contentHashes[stripped] = hashString
        return prefix + hashedPath(Path(stripped), hash: hashString).string
      } catch {
        return path
      }
    }
  }

  /// Copy hashed versions of files that were referenced via `Saga.hashed()`, next to the regular copy.
  func copyHashedFiles() throws {
    for resource in resources {
      guard let hash = contentHashes[resource.relativeDestination.string] else { continue }
      let destination = outputPath + hashedPath(resource.relativeDestination, hash: hash)
      try fileIO.mkpath(destination.parent())
      try fileIO.copy(resource.absoluteSource, destination)
    }
  }
}
