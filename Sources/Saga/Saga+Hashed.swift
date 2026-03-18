import Foundation

private nonisolated(unsafe) var _hashFunction: ((String) -> String)?
private let _hashLock = NSLock()

func setHashFunction(_ fn: ((String) -> String)?) {
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
