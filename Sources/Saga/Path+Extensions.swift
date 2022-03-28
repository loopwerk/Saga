import PathKit
import Foundation

public extension Path {
  var modificationDate: Date? {
    return self.attributes[.modificationDate] as? Date
  }

  var url: String {
    var url = "/" + self.string
    if url.hasSuffix("/index.html") {
      url.removeLast(10)
    }
    return url
  }

  func makeOutputPath(itemWriteMode: ItemWriteMode) -> Path {
    switch itemWriteMode {
      case .keepAsFile:
        return self.parent() + (self.lastComponentWithoutExtension.slugified + ".html")
      case .moveToSubfolder:
        return self.parent() + self.lastComponentWithoutExtension.slugified + "index.html"
    }
  }

  func relativePath(from: Path) throws -> Path {
    guard self.string.hasPrefix(from.string) else {
      return self
    }
    let index = self.string.index(self.string.startIndex, offsetBy: from.string.count)
    return Path(String(self.string[index...]).removingPrefix("/"))
  }
}

extension Path: Decodable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let decodedString = try container.decode(String.self)
    self.init(decodedString)
  }
}

internal extension Path {
  func resolveSwiftPackageFolder() throws -> Path {
    var nextFolder = parent()

    while nextFolder.isDirectory {
      if nextFolder.containsFile(named: "Package.swift") {
        return nextFolder
      }

      nextFolder = nextFolder.parent()
    }

    throw NSError(domain: "Could not resolve Swift package folder", code: 0, userInfo: nil)
  }

  func containsFile(named file: Path) -> Bool {
    return (self + file).isFile
  }

  var attributes: [FileAttributeKey : Any] {
    return (try? FileManager.default.attributesOfItem(atPath: self.string)) ?? [:]
  }
}

private extension String {
  func removingPrefix(_ prefix: String) -> String {
    guard hasPrefix(prefix) else { return self }
    return String(dropFirst(prefix.count))
  }

  func removingSuffix(_ suffix: String) -> String {
    guard hasSuffix(suffix) else { return self }
    return String(dropLast(suffix.count))
  }
}
