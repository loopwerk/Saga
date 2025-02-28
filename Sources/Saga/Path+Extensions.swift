import Foundation
import PathKit

public extension Path {
  var creationDate: Date? {
    return attributes[.creationDate] as? Date
  }

  var modificationDate: Date? {
    return attributes[.modificationDate] as? Date
  }

  var url: String {
    var url = "/" + string
    if url.hasSuffix("/index.html") {
      url.removeLast(10)
    }
    return url
  }

  func makeOutputPath(itemWriteMode: ItemWriteMode) -> Path {
    switch itemWriteMode {
      case .keepAsFile:
        return parent() + (lastComponentWithoutExtension.slugified + ".html")
      case .moveToSubfolder:
        if lastComponentWithoutExtension.slugified == "index" {
          return parent() + (lastComponentWithoutExtension.slugified + ".html")
        } else {
          return parent() + lastComponentWithoutExtension.slugified + "index.html"
        }
    }
  }

  func relativePath(from: Path) throws -> Path {
    guard string.hasPrefix(from.string) else {
      return self
    }
    let index = string.index(string.startIndex, offsetBy: from.string.count)
    return Path(String(string[index...]).removingPrefix("/"))
  }
}

extension Path: Decodable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let decodedString = try container.decode(String.self)
    self.init(decodedString)
  }
}

public extension Path {
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

  var attributes: [FileAttributeKey: Any] {
    return (try? FileManager.default.attributesOfItem(atPath: string)) ?? [:]
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
