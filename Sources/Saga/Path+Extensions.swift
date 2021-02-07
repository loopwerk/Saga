import PathKit
import Foundation

public extension Path {
  func makeOutputPath(pageWriteMode: PageWriteMode) -> Path {
    switch pageWriteMode {
      case .keepAsFile:
        return self.parent() + (self.lastComponentWithoutExtension.slugify() + ".html")
      case .moveToSubfolder:
        return self.parent() + self.lastComponentWithoutExtension.slugify() + "index.html"
    }
  }

  func relativePath(from: Path) throws -> Path {
    guard self.string.hasPrefix(from.string) else {
      return self
    }
    let index = self.string.index(self.string.startIndex, offsetBy: from.string.count)
    return Path(String(self.string[index...]).removingPrefix("/"))
  }

  var attributes: [FileAttributeKey : Any] {
    return (try? FileManager.default.attributesOfItem(atPath: self.string)) ?? [:]
  }

  var modificationDate: Date? {
    return self.attributes[.modificationDate] as? Date
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
