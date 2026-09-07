import Foundation
@testable import Saga
import SagaPathKit

extension FileIO {
  static let mock = Self(
    resolveSwiftPackageFolder: { _ in "root" },
    findFiles: { _ in ["test.md", "test2.md", "style.css"] },
    deletePath: { _ in },
    write: { _, _ in },
    mkpath: { _ in },
    read: { _ in Data("mock-content".utf8) },
    copy: { _, _ in },
    creationDate: { path in
      if path == "test2.md" {
        return Date(timeIntervalSince1970: 1_735_729_200)
      } else {
        return Date(timeIntervalSince1970: 1_704_106_800)
      }
    },
    modificationDate: { path in
      if path == "test2.md" {
        return Date(timeIntervalSince1970: 1_735_729_200)
      } else {
        return Date(timeIntervalSince1970: 1_704_106_800)
      }
    },
    log: { _ in }
  )
}

extension Reader {
  static func mock(frontmatter: [String: String]) -> Self {
    return Self(supportedExtensions: ["md"]) { absoluteSource in
      (title: "Test", body: "<p>\(absoluteSource)</p>", frontmatter: frontmatter)
    }
  }

  static var mockImage: Self {
    Self(supportedExtensions: ["jpg", "jpeg", "png"], copySourceFiles: true) { absoluteSource in
      (title: absoluteSource.lastComponentWithoutExtension, body: "", frontmatter: nil)
    }
  }
}

struct TaggedMetadata: Metadata {
  let tags: [String]
}

struct WrittenPage: Equatable {
  let destination: Path
  let content: String
}

struct CopiedFile: Equatable {
  let origin: Path
  let destination: Path
}

/// Thread-safe collector for values captured from concurrently running writers and hooks.
final class Recorder<T>: @unchecked Sendable {
  private let queue = DispatchQueue(label: "recorder", attributes: .concurrent)
  private var storage: [T] = []

  @Sendable func append(_ value: T) {
    queue.sync(flags: .barrier) { storage.append(value) }
  }

  var values: [T] {
    queue.sync { storage }
  }
}

extension Recorder where T == WrittenPage {
  /// Drop-in replacement for `FileIO.write` that records every written page.
  @Sendable func record(_ destination: Path, _ content: String) {
    append(WrittenPage(destination: destination, content: content))
  }
}

extension Recorder where T == CopiedFile {
  /// Drop-in replacement for `FileIO.copy` that records every copied file.
  @Sendable func record(_ origin: Path, _ destination: Path) {
    append(CopiedFile(origin: origin, destination: destination))
  }
}
