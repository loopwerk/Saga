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

@available(*, deprecated, message: "Use Saga.hashed() instead")
public func hashed(_ path: String) -> String {
  return Saga.hashed(path)
}

public extension Saga {
  /// Returns a cache-busted file path by inserting a content hash into the filename.
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

    setHashFunction { [weak self] path in
      guard let self else { return path }
      let stripped = path.hasPrefix("/") ? String(path.dropFirst()) : path
      guard let file = files.first(where: { $0.relativePath.string == stripped }) else {
        return path
      }

      if let cached = contentHashes[stripped] {
        let p = Path(stripped)
        let ext = p.extension ?? ""
        let name = p.parent() + Path(p.lastComponentWithoutExtension + "-" + cached + (ext.isEmpty ? "" : ".\(ext)"))
        return (path.hasPrefix("/") ? "/" : "") + name.string
      }

      do {
        let data = try fileIO.read(file.path)
        let digest = Insecure.MD5.hash(data: data)
        let hashString = String(digest.map { String(format: "%02x", $0) }.joined().prefix(8))
        contentHashes[stripped] = hashString

        let p = Path(stripped)
        let ext = p.extension ?? ""
        let name = p.parent() + Path(p.lastComponentWithoutExtension + "-" + hashString + (ext.isEmpty ? "" : ".\(ext)"))
        return (path.hasPrefix("/") ? "/" : "") + name.string
      } catch {
        return path
      }
    }
  }

  /// Copy hashed versions of files that were referenced via `Saga.hashed()`.
  func copyHashedFiles() throws {
    for file in unhandledFiles where contentHashes[file.relativePath.string] != nil {
      let relativePath = file.relativePath
      let ext = relativePath.extension ?? ""
      let hashedName = relativePath.lastComponentWithoutExtension + "-" + contentHashes[relativePath.string]! + (ext.isEmpty ? "" : ".\(ext)")
      let hashedRelativePath = relativePath.parent() + Path(hashedName)
      let destination = outputPath + hashedRelativePath
      try fileIO.mkpath(destination.parent())
      try fileIO.copy(file.path, destination)
    }
  }
}
