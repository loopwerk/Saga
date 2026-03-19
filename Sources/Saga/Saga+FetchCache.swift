import Foundation
import SagaPathKit

enum CacheError: Error {
  case noCacheDir
}

extension Saga {
  /// The directory used to cache fetched items, set via the `SAGA_CACHE_DIR` environment variable.
  var cachePath: Path? {
    ProcessInfo.processInfo.environment["SAGA_CACHE_DIR"].map { Path($0) }
  }

  func loadCachedItems<M: Metadata>(key: String) throws -> [Item<M>] {
    guard let cachePath else {
      throw CacheError.noCacheDir
    }

    let cacheFile = cachePath + Path("\(key).json")
    let data = try fileIO.read(cacheFile)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode([Item<M>].self, from: data)
  }

  func cacheItems<M: Metadata>(_ items: [Item<M>], key: String) {
    guard let cachePath else { return }

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(items) else { return }
    guard let string = String(data: data, encoding: .utf8) else { return }
    let cacheFile = cachePath + Path("\(key).json")
    try? fileIO.mkpath(cachePath)
    try? fileIO.write(cacheFile, string)
  }
}
