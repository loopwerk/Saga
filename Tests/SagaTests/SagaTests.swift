import Foundation
@testable import Saga
import SagaPathKit
import XCTest

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
    }
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

final class SagaTests: XCTestCase, @unchecked Sendable {
  func testInitializer() throws {
    nonisolated(unsafe) var deletePathCalled = false

    var mock = FileIO.mock
    mock.deletePath = { _ in
      deletePathCalled = true
    }

    let saga = try Saga(input: "input", output: "output", fileIO: mock)
    XCTAssertEqual(saga.rootPath, "root")
    XCTAssertEqual(saga.inputPath, "root/input")
    XCTAssertEqual(saga.outputPath, "root/output")
    XCTAssertEqual(saga.files.count, 3)
    XCTAssertEqual(saga.files[0].path, "test.md")
    XCTAssertEqual(saga.files[1].path, "test2.md")
    XCTAssertEqual(saga.files[2].path, "style.css")
    XCTAssertEqual(saga.allItems.count, 0)
    XCTAssertEqual(deletePathCalled, false)
  }

  func testRegister() throws {
    let saga = try Saga(input: "input", output: "output", fileIO: .mock)
    XCTAssertEqual(saga.steps.count, 0)

    saga.register(metadata: EmptyMetadata.self, readers: [], writers: [])
    XCTAssertEqual(saga.steps.count, 1)
  }
  
  func testMakeSureEmptyPathHasNoComponents() {
    XCTAssertEqual(Path("").components, [])
  }

  func testReaderAndItemWriterAndListWriter() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []
    nonisolated(unsafe) var deletePathCalled = false

    var mock = FileIO.mock
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }
    mock.deletePath = { _ in
      deletePathCalled = true
    }

    let saga = try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        metadata: EmptyMetadata.self,
        readers: [
          .mock(frontmatter: [:]),
        ],
        writers: [
          .itemWriter { context in context.item.body },
          .listWriter({ context in context.items.map(\.body).joined(separator: "") }, output: "list.html"),
        ]
      )
      .run()

    // The readers turn Markdown files into Items
    XCTAssertEqual(saga.allItems.count, 2)
    XCTAssertEqual(saga.allItems[0].body, "<p>test2.md</p>")
    XCTAssertEqual(saga.allItems[1].body, "<p>test.md</p>")

    // File tracking
    XCTAssertEqual(saga.files.count, 3)
    XCTAssertEqual(saga.files[0].path, "test.md")
    XCTAssertEqual(saga.files[1].path, "test2.md")
    XCTAssertEqual(saga.files[2].path, "style.css")

    XCTAssertEqual(deletePathCalled, true)

    // And when the writer runs, the Items get written to disk
    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }
    XCTAssertEqual(finalWrittenPages.count, 3)
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/test2/index.html", content: "<p>test2.md</p>")))
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/test/index.html", content: "<p>test.md</p>")))
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/list.html", content: "<p>test2.md</p><p>test.md</p>")))
  }

  func testFilterItems() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    let saga = try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        metadata: EmptyMetadata.self,
        readers: [
          .mock(frontmatter: [:]),
        ],
        filter: { _ in return false },
        writers: [
          .itemWriter { context in context.item.body },
          .listWriter({ context in context.items.map(\.body).joined(separator: "") }, output: "list.html"),
        ]
      )
      .register(
        metadata: EmptyMetadata.self,
        readers: [
          .mock(frontmatter: [:]),
        ],
        writers: [
          .itemWriter { context in context.item.body },
          .listWriter({ context in context.items.map(\.body).joined(separator: "") }, output: "list.html"),
        ]
      )
      .run()

    // The readers turn Markdown files into Items and track them in files
    XCTAssertEqual(saga.files.count, 3)

    // And when the writer runs, the Items get written to disk
    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }
    XCTAssertEqual(finalWrittenPages.count, 2)
    XCTAssertEqual(finalWrittenPages, [WrittenPage(destination: "root/output/list.html", content: ""), WrittenPage(destination: "root/output/list.html", content: "")])
  }

  func testFilterButNotHandledItems() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    let saga = try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        metadata: EmptyMetadata.self,
        readers: [
          .mock(frontmatter: [:]),
        ],
        filter: { _ in return false },
        claimExcludedItems: false,
        writers: [
          .itemWriter { context in context.item.body },
          .listWriter({ context in context.items.map(\.body).joined(separator: "") }, output: "list.html"),
        ]
      )
      .register(
        metadata: EmptyMetadata.self,
        readers: [
          .mock(frontmatter: [:]),
        ],
        writers: [
          .itemWriter { context in context.item.body },
          .listWriter({ context in context.items.map(\.body).joined(separator: "") }, output: "list.html"),
        ]
      )
      .run()

    // The readers turn Markdown files into Items and track them in files
    XCTAssertEqual(saga.files.count, 3)

    // And when the writer runs, the Items get written to disk
    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }
    XCTAssertEqual(finalWrittenPages.count, 4)
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/list.html", content: "")))
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/list.html", content: "<p>test2.md</p><p>test.md</p>")))
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/test2/index.html", content: "<p>test2.md</p>")))
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/test/index.html", content: "<p>test.md</p>")))
  }

  /// If the frontmatter contains a date property then this should be set to the item's date
  func testDateFromFrontMatter() async throws {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"

    let saga = try await Saga(input: "input", output: "output", fileIO: FileIO.mock)
      .register(
        metadata: EmptyMetadata.self,
        readers: [
          .mock(frontmatter: ["date": "2025-01-02"]),
        ],
        writers: []
      )
      .run()

    XCTAssertEqual(saga.allItems.first?.date, formatter.date(from: "2025-01-02"))
  }

  func testYearWriter() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        metadata: EmptyMetadata.self,
        readers: [
          .mock(frontmatter: [:]),
        ],
        writers: [
          .yearWriter { context in context.items.map(\.body).joined(separator: "") },
        ]
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }
    XCTAssertEqual(finalWrittenPages.count, 2)
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/2024/index.html", content: "<p>test.md</p>")))
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/2025/index.html", content: "<p>test2.md</p>")))
  }

  func testTagWriter() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        metadata: TaggedMetadata.self,
        readers: [
          .mock(frontmatter: ["tags": "one, with space"]),
        ],
        writers: [
          .tagWriter({ context in context.items.map(\.body).joined(separator: "") }, tags: \.metadata.tags),
        ]
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }
    XCTAssertEqual(finalWrittenPages.count, 2)
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/tag/one/index.html", content: "<p>test2.md</p><p>test.md</p>")))
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/tag/with-space/index.html", content: "<p>test2.md</p><p>test.md</p>")))
  }

  func testStaticFiles() async throws {
    let writtenFilesQueue = DispatchQueue(label: "writtenFiles", attributes: .concurrent)
    nonisolated(unsafe) var writtenFiles: [Path] = []

    var mock = FileIO.mock
    mock.copy = { origin, destination in
      writtenFilesQueue.sync(flags: .barrier) {
        writtenFiles.append(destination)
      }
    }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        metadata: TaggedMetadata.self,
        readers: [
          .mock(frontmatter: ["tags": "one, with space"]),
        ],
        writers: [
        ]
      )
      .run()

    let finalWrittenFiles = writtenFilesQueue.sync { writtenFiles }
    XCTAssertEqual(finalWrittenFiles, ["root/output/style.css"])
  }

  func testWriteMode() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    let saga = try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        metadata: EmptyMetadata.self,
        readers: [
          .mock(frontmatter: [:]),
        ],
        itemWriteMode: .keepAsFile,
        writers: [
          .itemWriter { context in context.item.body },
        ]
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }
    let items = saga.allItems
    XCTAssertEqual(items.first(where: { $0.title == "Test" && $0.relativeSource == "test.md" })?.relativeDestination, "test.html")
    XCTAssertEqual(items.first(where: { $0.title == "Test" && $0.relativeSource == "test2.md" })?.relativeDestination, "test2.html")
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/test.html", content: "<p>test.md</p>")))
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/test2.html", content: "<p>test2.md</p>")))
  }

  func testItemWriterPreviousNext() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        metadata: EmptyMetadata.self,
        readers: [
          .mock(frontmatter: [:]),
        ],
        writers: [
          .itemWriter { context in
            let prev = context.previous?.body ?? "none"
            let next = context.next?.body ?? "none"
            return "\(context.item.body)|prev:\(prev)|next:\(next)"
          },
        ]
      )
      .run()

    // Items are sorted by date descending: test2.md (2025) comes first, test.md (2024) second
    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }
    XCTAssertEqual(finalWrittenPages.count, 2)
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/test2/index.html", content: "<p>test2.md</p>|prev:none|next:<p>test.md</p>")))
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/test/index.html", content: "<p>test.md</p>|prev:<p>test2.md</p>|next:none")))
  }

  func testCustomSorting() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        metadata: EmptyMetadata.self,
        readers: [
          .mock(frontmatter: [:]),
        ],
        // Sort by date ascending instead of the default descending
        sorting: { $0.date < $1.date },
        writers: [
          .itemWriter { context in
            let prev = context.previous?.body ?? "none"
            let next = context.next?.body ?? "none"
            return "\(context.item.body)|prev:\(prev)|next:\(next)"
          },
        ]
      )
      .run()

    // With date ascending: test.md (2024) comes first, test2.md (2025) second
    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }
    XCTAssertEqual(finalWrittenPages.count, 2)
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/test/index.html", content: "<p>test.md</p>|prev:none|next:<p>test2.md</p>")))
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/test2/index.html", content: "<p>test2.md</p>|prev:<p>test.md</p>|next:none")))
  }

  func testFolderGlob() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in ["folder/sub1/a.md", "folder/sub1/b.md", "folder/sub2/c.md", "style.css"] }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        folder: "folder/**",
        metadata: EmptyMetadata.self,
        readers: [
          .mock(frontmatter: [:]),
        ],
        writers: [
          .itemWriter { context in
            let prev = context.previous?.body ?? "none"
            let next = context.next?.body ?? "none"
            return "\(context.item.body)|prev:\(prev)|next:\(next)"
          },
          .listWriter { context in
            context.items.map(\.body).joined(separator: ",")
          },
        ]
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }

    // itemWriter: a.md and b.md are scoped to sub1, c.md is alone in sub2
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/folder/sub1/a/index.html" }))
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/folder/sub1/b/index.html" }))
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/folder/sub2/c/index.html" }))

    // c.md is the only item in sub2, so it has no previous or next
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/folder/sub2/c/index.html", content: "<p>folder/sub2/c.md</p>|prev:none|next:none")))

    // a.md and b.md should reference each other (scoped to sub1), not c.md
    let aPage = try XCTUnwrap(finalWrittenPages.first(where: { $0.destination == "root/output/folder/sub1/a/index.html" }))
    let bPage = try XCTUnwrap(finalWrittenPages.first(where: { $0.destination == "root/output/folder/sub1/b/index.html" }))
    XCTAssertFalse(aPage.content.contains("sub2"))
    XCTAssertFalse(bPage.content.contains("sub2"))

    // listWriter: generates one index per subfolder
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/folder/sub1/index.html" && $0.content.contains("sub1/a.md") && $0.content.contains("sub1/b.md") }))
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/folder/sub2/index.html", content: "<p>folder/sub2/c.md</p>")))
  }

  func testNestedSimple() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in ["folder/sub1/a.md", "folder/sub1/b.md", "folder/sub2/c.md", "style.css"] }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        folder: "folder",
        nested: { nested in
          nested.register(
            metadata: EmptyMetadata.self,
            readers: [.mock(frontmatter: [:])],
            writers: [
              .itemWriter { context in
                let prev = context.previous?.body ?? "none"
                let next = context.next?.body ?? "none"
                return "\(context.item.body)|prev:\(prev)|next:\(next)"
              },
              .listWriter { context in
                let prefix = context.subfolder ?? "none"
                return "\(prefix):" + context.items.map(\.body).joined(separator: ",")
              },
            ]
          )
        }
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }

    // itemWriter: a.md and b.md are scoped to sub1, c.md is alone in sub2
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/folder/sub1/a/index.html" }))
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/folder/sub1/b/index.html" }))
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/folder/sub2/c/index.html" }))

    // c.md is the only item in sub2, so it has no previous or next
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/folder/sub2/c/index.html", content: "<p>folder/sub2/c.md</p>|prev:none|next:none")))

    // a.md and b.md should reference each other (scoped to sub1), not c.md
    let aPage = try XCTUnwrap(finalWrittenPages.first(where: { $0.destination == "root/output/folder/sub1/a/index.html" }))
    let bPage = try XCTUnwrap(finalWrittenPages.first(where: { $0.destination == "root/output/folder/sub1/b/index.html" }))
    XCTAssertFalse(aPage.content.contains("sub2"))
    XCTAssertFalse(bPage.content.contains("sub2"))

    // listWriter: generates one index per subfolder, with subfolder name available
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/folder/sub1/index.html" && $0.content.hasPrefix("sub1:") }))
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/folder/sub2/index.html" && $0.content.hasPrefix("sub2:") }))
  }

  func testNestedWithOuterWriters() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in ["folder/sub1/a.md", "folder/sub1/b.md", "folder/sub2/c.md", "style.css"] }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    let saga = try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        folder: "folder",
        writers: [
          .listWriter { context in
            context.items.map { item in
              "\(item.title):\(item.children.count)"
            }.joined(separator: ",")
          },
        ],
        nested: { nested in
          nested.register(
            metadata: EmptyMetadata.self,
            readers: [.mock(frontmatter: [:])],
            writers: [
              .itemWriter { context in context.item.body },
            ]
          )
        }
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }

    // Outer listWriter should see fake parent items with children
    let listPage = finalWrittenPages.first(where: { $0.destination == "root/output/folder/index.html" })
    XCTAssertNotNil(listPage)
    XCTAssertTrue(try XCTUnwrap(listPage?.content.contains("sub1:2")))
    XCTAssertTrue(try XCTUnwrap(listPage?.content.contains("sub2:1")))

    // Nested items should be in allItems
    XCTAssertTrue(saga.allItems.count >= 3) // At least the 3 nested items + 2 fake parents
  }

  func testNestedDifferentReaders() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    struct AlbumMetadata: Metadata {}

    var mock = FileIO.mock
    mock.findFiles = { _ in ["photos/dogs/index.md", "photos/dogs/a.jpg", "photos/dogs/b.jpg", "photos/cats/index.md", "photos/cats/c.jpg"] }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    let saga = try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        folder: "photos",
        metadata: AlbumMetadata.self,
        readers: [.mock(frontmatter: [:])],
        writers: [
          .listWriter({ context in
            context.items.map { "\($0.title):\($0.children.count)" }.joined(separator: ",")
          }, output: "index.html"),
        ],
        nested: { nested in
          nested.register(
            metadata: EmptyMetadata.self,
            readers: [.mockImage],
            writers: [
              .itemWriter { context in
                let parentTitle = context.item.parent?.title ?? "none"
                return "\(context.item.title)|parent:\(parentTitle)"
              },
            ]
          )
        }
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }

    // Parent listWriter should see albums with children
    let listPage = finalWrittenPages.first(where: { $0.destination == "root/output/photos/index.html" })
    XCTAssertNotNil(listPage)
    XCTAssertTrue(try XCTUnwrap(listPage?.content.contains(":2"))) // dogs has 2 photos
    XCTAssertTrue(try XCTUnwrap(listPage?.content.contains(":1"))) // cats has 1 photo

    // Nested itemWriter should see parent
    let photoPages = finalWrittenPages.filter { $0.destination.string.contains(".jpg") || $0.content.contains("parent:") }
    for page in photoPages {
      XCTAssertTrue(page.content.contains("parent:Test"))
    }

    // Both parents and children should be in allItems
    let albumItems = saga.allItems.filter { $0 is Item<AlbumMetadata> }
    XCTAssertEqual(albumItems.count, 2)
  }

  func testNestedChildrenAccessor() async throws {
    struct PhotoMeta: Metadata {}

    var mock = FileIO.mock
    mock.findFiles = { _ in ["folder/sub1/a.jpg", "folder/sub1/b.jpg"] }
    mock.write = { _, _ in }

    let saga = try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        folder: "folder",
        writers: [],
        nested: { nested in
          nested.register(
            metadata: PhotoMeta.self,
            readers: [.mockImage],
            writers: []
          )
        }
      )
      .run()

    // Find the fake parent
    let parents = saga.allItems.filter { $0 is Item<EmptyMetadata> }
    XCTAssertEqual(parents.count, 1)
    let parent = try XCTUnwrap(parents[0] as? Item<EmptyMetadata>)

    // Typed children accessor
    let typedChildren = parent.children(as: PhotoMeta.self)
    XCTAssertEqual(typedChildren.count, 2)

    // Parent accessor from child
    let child = typedChildren[0]
    let typedParent = child.parent(as: EmptyMetadata.self)
    XCTAssertEqual(typedParent.title, "sub1")
  }

  func testNestedInNested() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in [
      "courses/math/algebra/lesson1.md",
      "courses/math/algebra/lesson2.md",
      "courses/math/calculus/lesson3.md",
      "courses/science/physics/lesson4.md",
    ] }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    let saga = try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        folder: "courses",
        writers: [
          .listWriter { context in
            // Outer: list of courses (math, science)
            context.items.map { "\($0.title):\($0.children.count)" }.joined(separator: ",")
          },
        ],
        nested: { nested in
          nested.register(
            // Middle level: topics (algebra, calculus, physics)
            writers: [
              .listWriter { context in
                context.items.map { "\($0.title):\($0.children.count)" }.joined(separator: ",")
              },
            ],
            nested: { nested2 in
              nested2.register(
                // Leaf level: lessons
                metadata: EmptyMetadata.self,
                readers: [.mock(frontmatter: [:])],
                writers: [
                  .itemWriter { context in context.item.body },
                ]
              )
            }
          )
        }
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }

    // Leaf lessons should be written
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/courses/math/algebra/lesson1/index.html" }))
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/courses/math/algebra/lesson2/index.html" }))
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/courses/math/calculus/lesson3/index.html" }))
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/courses/science/physics/lesson4/index.html" }))

    // Middle-level listWriter: one per course subfolder (math, science)
    let mathTopics = finalWrittenPages.first(where: { $0.destination == "root/output/courses/math/index.html" })
    XCTAssertNotNil(mathTopics)
    XCTAssertTrue(try XCTUnwrap(mathTopics?.content.contains("algebra:2")))
    XCTAssertTrue(try XCTUnwrap(mathTopics?.content.contains("calculus:1")))

    let scienceTopics = finalWrittenPages.first(where: { $0.destination == "root/output/courses/science/index.html" })
    XCTAssertNotNil(scienceTopics)
    XCTAssertTrue(try XCTUnwrap(scienceTopics?.content.contains("physics:1")))

    // Outer listWriter: courses overview
    let coursesPage = finalWrittenPages.first(where: { $0.destination == "root/output/courses/index.html" })
    XCTAssertNotNil(coursesPage)
    XCTAssertTrue(try XCTUnwrap(coursesPage?.content.contains("math:2")))
    XCTAssertTrue(try XCTUnwrap(coursesPage?.content.contains("science:1")))

    // All items should be in allItems
    XCTAssertTrue(saga.allItems.count >= 4) // At least the 4 lessons
  }

  func testNestedInNestedWithDifferentMetadata() async throws {
    struct ArtistMetadata: Metadata {}
    struct AlbumMetadata: Metadata {}
    struct TrackMetadata: Metadata {}

    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in [
      "artists/beatles/index.md",
      "artists/beatles/abbey-road/index.md",
      "artists/beatles/abbey-road/tracks/come-together.md",
      "artists/beatles/abbey-road/tracks/something.md",
      "artists/beatles/let-it-be/index.md",
      "artists/beatles/let-it-be/tracks/get-back.md",
      "artists/beatles/yellow-submarine/index.md",
      "artists/radiohead/index.md",
      "artists/radiohead/ok-computer/index.md",
      "artists/radiohead/ok-computer/tracks/paranoid-android.md",
    ] }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    let saga = try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        folder: "artists",
        metadata: ArtistMetadata.self,
        readers: [.mock(frontmatter: [:])],
        writers: [
          .listWriter({ context in
            context.items.map { "\($0.title):\($0.children.count)albums" }.joined(separator: ",")
          }, output: "index.html"),
        ],
        nested: { artists in
          artists.register(
            metadata: AlbumMetadata.self,
            readers: [.mock(frontmatter: [:])],
            writers: [
              .itemWriter { context in
                let artist = context.item.parent?.title ?? "none"
                let tracks = context.item.children.count
                return "album:\(context.item.title)|artist:\(artist)|tracks:\(tracks)"
              },
            ],
            nested: { albums in
              albums.register(
                folder: "tracks",
                metadata: TrackMetadata.self,
                readers: [.mock(frontmatter: [:])],
                writers: [
                  .itemWriter { context in
                    let album = context.item.parent?.title ?? "none"
                    return "track:\(context.item.title)|album:\(album)"
                  },
                ]
              )
            }
          )
        }
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }

    // === Item counts by type ===
    let artistItems = saga.allItems.compactMap { $0 as? Item<ArtistMetadata> }
    let albumItems = saga.allItems.compactMap { $0 as? Item<AlbumMetadata> }
    let trackItems = saga.allItems.compactMap { $0 as? Item<TrackMetadata> }
    XCTAssertEqual(artistItems.count, 2, "Expected 2 artists (beatles, radiohead)")
    XCTAssertEqual(albumItems.count, 4, "Expected 4 albums (abbey-road, let-it-be, yellow-submarine, ok-computer)")
    XCTAssertEqual(trackItems.count, 4, "Expected 4 tracks")
    XCTAssertEqual(saga.allItems.count, 10, "Expected 10 total items (2 artists + 4 albums + 4 tracks)")

    // === Parent/child wiring ===
    // Artists should have albums as direct children (not tracks)
    let beatles = try XCTUnwrap(artistItems.first(where: { $0.relativeSource.string.contains("beatles") }))
    let radiohead = try XCTUnwrap(artistItems.first(where: { $0.relativeSource.string.contains("radiohead") }))
    XCTAssertEqual(beatles.children.count, 3, "Beatles should have 3 album children")
    XCTAssertEqual(radiohead.children.count, 1, "Radiohead should have 1 album child")

    // Albums should have tracks as direct children
    let abbeyRoad = try XCTUnwrap(albumItems.first(where: { $0.relativeSource.string.contains("abbey-road") }))
    let letItBe = try XCTUnwrap(albumItems.first(where: { $0.relativeSource.string.contains("let-it-be") }))
    let okComputer = try XCTUnwrap(albumItems.first(where: { $0.relativeSource.string.contains("ok-computer") }))
    XCTAssertEqual(abbeyRoad.children.count, 2, "Abbey Road should have 2 tracks")
    XCTAssertEqual(letItBe.children.count, 1, "Let It Be should have 1 track")
    XCTAssertEqual(okComputer.children.count, 1, "OK Computer should have 1 track")
    let yellowSubmarine = try XCTUnwrap(albumItems.first(where: { $0.relativeSource.string.contains("yellow-submarine") }))
    XCTAssertEqual(yellowSubmarine.children.count, 0, "Yellow Submarine should have 0 tracks")

    // Albums should have artist as parent
    XCTAssertTrue(abbeyRoad.parent === beatles)
    XCTAssertTrue(letItBe.parent === beatles)
    XCTAssertTrue(yellowSubmarine.parent === beatles)
    XCTAssertTrue(okComputer.parent === radiohead)

    // Tracks should have album as parent
    for track in trackItems {
      XCTAssertNotNil(track.parent, "Every track should have a parent album")
      XCTAssertTrue(albumItems.contains(where: { $0 === track.parent }), "Track parent should be an album")
    }

    // === Writers at every level ===
    // Artist listWriter
    let artistList = try XCTUnwrap(finalWrittenPages.first(where: { $0.destination == "root/output/artists/index.html" }))
    XCTAssertEqual(artistList.content, "Test:3albums,Test:1albums")

    // Album itemWriter — one page per album (including childless yellow-submarine)
    let albumPages = finalWrittenPages.filter { $0.content.hasPrefix("album:") }
    XCTAssertEqual(albumPages.count, 4, "Expected 4 album pages")
    XCTAssertTrue(albumPages.contains(WrittenPage(destination: "root/output/artists/beatles/abbey-road/index.html", content: "album:Test|artist:Test|tracks:2")))
    XCTAssertTrue(albumPages.contains(WrittenPage(destination: "root/output/artists/beatles/let-it-be/index.html", content: "album:Test|artist:Test|tracks:1")))
    XCTAssertTrue(albumPages.contains(WrittenPage(destination: "root/output/artists/beatles/yellow-submarine/index.html", content: "album:Test|artist:Test|tracks:0")))
    XCTAssertTrue(albumPages.contains(WrittenPage(destination: "root/output/artists/radiohead/ok-computer/index.html", content: "album:Test|artist:Test|tracks:1")))

    // Track itemWriter — one page per track
    let trackPages = finalWrittenPages.filter { $0.content.hasPrefix("track:") }
    XCTAssertEqual(trackPages.count, 4, "Expected 4 track pages")
    XCTAssertTrue(trackPages.contains(where: { $0.destination == "root/output/artists/beatles/abbey-road/tracks/come-together/index.html" }))
    XCTAssertTrue(trackPages.contains(where: { $0.destination == "root/output/artists/beatles/abbey-road/tracks/something/index.html" }))
    XCTAssertTrue(trackPages.contains(where: { $0.destination == "root/output/artists/beatles/let-it-be/tracks/get-back/index.html" }))
    XCTAssertTrue(trackPages.contains(where: { $0.destination == "root/output/artists/radiohead/ok-computer/tracks/paranoid-android/index.html" }))
    // Every track page should reference its parent album (mock reader gives title "Test")
    for page in trackPages {
      XCTAssertTrue(page.content.contains("|album:Test"), "Track page should reference parent album: \(page.content)")
    }

    // Total written pages: 1 artist list + 4 album pages + 4 track pages = 9
    XCTAssertEqual(finalWrittenPages.count, 9)
  }

  func testSubfolderIsNilWithoutNesting() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        metadata: EmptyMetadata.self,
        readers: [
          .mock(frontmatter: [:]),
        ],
        writers: [
          .listWriter { context in
            context.subfolder?.string ?? "nil"
          },
        ]
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/index.html", content: "nil")))
  }

  func testMetadataDecoder() throws {
    struct TestMetadata: Metadata {
      let tags: [String]
      let date: Date
      let url: URL
    }

    let metadataDict: [String: String] = [
      "tags": "one, two",
      "date": "2021-02-02",
      "url": "https://www.example.com",
    ]

    let decoder = makeMetadataDecoder(for: metadataDict)
    let decoded = try TestMetadata(from: decoder)

    XCTAssertEqual(decoded.tags, ["one", "two"])
    XCTAssertEqual(decoded.url, URL(string: "https://www.example.com"))
  }

  func testSlugified() {
    XCTAssertEqual("one two".slugified, "one-two")
    XCTAssertEqual("one - two".slugified, "one-two")
    XCTAssertEqual("One Two".slugified, "one-two")
    XCTAssertEqual("One! .Two@".slugified, "one-two")
    XCTAssertEqual("one-two".slugified, "one-two")
    XCTAssertEqual("one_two".slugified, "one_two")
    XCTAssertEqual("ONE-TWO".slugified, "one-two")
  }

  func testRegisterFetch() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in [] }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    let saga = try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        metadata: EmptyMetadata.self,
        fetch: {
          [
            Item(title: "Fetched One", body: "<p>one</p>", date: Date(timeIntervalSince1970: 1_704_106_800), metadata: EmptyMetadata()),
            Item(title: "Fetched Two", body: "<p>two</p>", date: Date(timeIntervalSince1970: 1_735_729_200), metadata: EmptyMetadata()),
          ]
        },
        writers: [
          .listWriter({ context in context.items.map(\.body).joined(separator: "") }, output: "fetched/index.html"),
        ]
      )
      .run()

    // Items are sorted by date descending
    XCTAssertEqual(saga.allItems.count, 2)
    XCTAssertEqual(saga.allItems[0].title, "Fetched Two")
    XCTAssertEqual(saga.allItems[1].title, "Fetched One")

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }
    XCTAssertEqual(finalWrittenPages.count, 1)
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/fetched/index.html", content: "<p>two</p><p>one</p>")))
  }

  func testRegisterFetchWithFileBasedItems() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    let saga = try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: [:])],
        writers: [
          .itemWriter { context in context.item.body },
        ]
      )
      .register(
        metadata: EmptyMetadata.self,
        fetch: {
          [
            Item(title: "Remote Item", body: "<p>remote</p>", date: Date(timeIntervalSince1970: 1_720_000_000), metadata: EmptyMetadata()),
          ]
        },
        writers: [
          .listWriter({ context in context.items.map(\.body).joined(separator: "") }, output: "remote/index.html"),
        ]
      )
      .run()

    // allItems contains both file-based and fetched items, sorted by date descending
    XCTAssertEqual(saga.allItems.count, 3)
    XCTAssertEqual(saga.allItems[0].title, "Test") // test2.md 2025
    XCTAssertEqual(saga.allItems[1].title, "Remote Item") // 2024-07
    XCTAssertEqual(saga.allItems[2].title, "Test") // test.md 2024

    // Writers for both steps should have run
    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }
    XCTAssertEqual(finalWrittenPages.count, 3)
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/test2/index.html", content: "<p>test2.md</p>")))
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/test/index.html", content: "<p>test.md</p>")))
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/remote/index.html", content: "<p>remote</p>")))
  }

  func testCreatePage() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: [:])],
        writers: [
          .itemWriter { context in context.item.body },
        ]
      )
      .createPage("index.html") { context in
        let titles = context.allItems.map(\.title).joined(separator: ", ")
        return "<h1>Home</h1><p>\(titles)</p>"
      }
      .createPage("404.html") { _ in
        "<h1>Not Found</h1>"
      }
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }

    // itemWriter wrote 2 items + createPage wrote 2 pages
    XCTAssertEqual(finalWrittenPages.count, 4)

    // The homepage has access to allItems
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/index.html", content: "<h1>Home</h1><p>Test, Test</p>")))

    // The 404 page was written
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/404.html", content: "<h1>Not Found</h1>")))
  }

  func testCreatePageOutputPath() async throws {
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in [] }
    mock.write = { destination, content in
      writtenPages.append(.init(destination: destination, content: content))
    }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .createPage("search/index.html") { context in
        "\(context.outputPath)"
      }
      .run()

    XCTAssertEqual(writtenPages.count, 1)
    XCTAssertTrue(writtenPages.contains(WrittenPage(destination: "root/output/search/index.html", content: "search/index.html")))
  }

  func testHash() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    nonisolated(unsafe) var copiedFiles: [(Path, Path)] = []
    let copiedFilesQueue = DispatchQueue(label: "copiedFiles", attributes: .concurrent)
    mock.copy = { origin, destination in
      copiedFilesQueue.sync(flags: .barrier) {
        copiedFiles.append((origin, destination))
      }
    }

    // read returns fixed content so the hash is deterministic
    mock.read = { _ in Data("hello".utf8) }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: [:])],
        writers: [
          .itemWriter { context in
            let hashed = hashed("/style.css")
            return "<link href=\"\(hashed)\">"
          },
        ]
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }
    // The hash of "hello" via MD5 is 5d41402abc4b2a76b9719d911017c592, first 8 chars: 5d41402a
    let expectedPath = "/style-5d41402a.css"
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.content == "<link href=\"\(expectedPath)\">" }))

    // The hashed copy should have been created
    let finalCopiedFiles = copiedFilesQueue.sync { copiedFiles }
    XCTAssertTrue(finalCopiedFiles.contains(where: { $0.1 == Path("root/output/style-5d41402a.css") }))
  }

  func testHashWithoutLeadingSlash() async throws {
    var mock = FileIO.mock
    mock.read = { _ in Data("hello".utf8) }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: [:])],
        writers: [
          .itemWriter { _ in
            let hashed = hashed("style.css")
            // Without leading slash, result should also have no leading slash
            XCTAssertEqual(hashed, "style-5d41402a.css")
            return ""
          },
        ]
      )
      .run()
  }

  func testHashUnknownFile() async throws {
    var mock = FileIO.mock
    mock.read = { _ in Data() }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: [:])],
        writers: [
          .itemWriter { _ in
            let hashed = hashed("/nonexistent.css")
            // Unknown file should return path unchanged
            XCTAssertEqual(hashed, "/nonexistent.css")
            return ""
          },
        ]
      )
      .run()
  }

  func testPostProcess() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: [:])],
        writers: [
          .itemWriter { context in context.item.body },
        ]
      )
      .postProcess { content, _ in
        content.uppercased()
      }
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }
    XCTAssertEqual(finalWrittenPages.count, 2)
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/test/index.html", content: "<P>TEST.MD</P>")))
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/test2/index.html", content: "<P>TEST2.MD</P>")))
  }

  func testPostProcessWithCreatePage() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: [:])],
        writers: [
          .itemWriter { context in context.item.body },
        ]
      )
      .createPage("index.html") { _ in "<h1>Home</h1>" }
      .postProcess { content, _ in
        content.uppercased()
      }
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/index.html", content: "<H1>HOME</H1>")))
  }

  func testPostProcessReceivesRelativePath() async throws {
    nonisolated(unsafe) var receivedPaths: [Path] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in [] }
    mock.write = { _, _ in }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .createPage("search/index.html") { _ in "content" }
      .postProcess { content, path in
        receivedPaths.append(path)
        return content
      }
      .run()

    XCTAssertEqual(receivedPaths, [Path("search/index.html")])
  }

  func testGeneratedPages() async throws {
    var mock = FileIO.mock
    mock.findFiles = { _ in ["articles/test.md", "articles/test2.md", "style.css"] }
    mock.write = { _, _ in }

    let saga = try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        folder: "articles",
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: [:])],
        writers: [
          .itemWriter { context in context.item.body },
          .listWriter({ context in "" }, output: "list.html"),
        ]
      )
      .createPage("index.html") { _ in "<h1>Home</h1>" }
      .createPage("404.html") { _ in "<h1>Not Found</h1>" }
      .run()

    let pages = saga.generatedPages.flatMap(\.values).map(\.string).sorted()
    XCTAssertEqual(pages, ["404.html", "articles/list.html", "articles/test/index.html", "articles/test2/index.html", "index.html"])
  }

  func testSitemap() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    mock.findFiles = { _ in ["articles/test.md", "articles/test2.md", "style.css"] }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        folder: "articles",
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: [:])],
        writers: [
          .itemWriter { context in context.item.body },
        ]
      )
      .createPage("404.html") { _ in "<h1>Not Found</h1>" }
      .createPage("sitemap.xml", using: sitemap(
        baseURL: try XCTUnwrap(URL(string: "https://example.com")),
        filter: { $0 != "404.html" }
      ))
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }
    let sitemapPage = finalWrittenPages.first(where: { $0.destination == "root/output/sitemap.xml" })
    XCTAssertNotNil(sitemapPage)

    let content = try XCTUnwrap(sitemapPage?.content)
    XCTAssertTrue(content.contains("<loc>https://example.com/articles/test/</loc>"))
    XCTAssertTrue(content.contains("<loc>https://example.com/articles/test2/</loc>"))
    XCTAssertFalse(content.contains("sitemap.xml"))
    XCTAssertFalse(content.contains("404.html"))
  }

  // MARK: - i18n Tests

  func testI18NDirectoryStyleLocaleTagging() async throws {
    var mock = FileIO.mock
    mock.findFiles = { _ in [
      "en/articles/hello.md",
      "en/articles/world.md",
      "nl/articles/hello.md",
      "nl/articles/world.md",
      "static/style.css",
    ] }
    mock.write = { _, _ in }

    let saga = try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en", style: .directory)
      .register(
        folder: "articles",
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: [:])],
        writers: []
      )
      .run()

    XCTAssertEqual(saga.allItems.count, 4)

    let enItems = saga.allItems.filter { $0.locale == "en" }
    let nlItems = saga.allItems.filter { $0.locale == "nl" }
    XCTAssertEqual(enItems.count, 2)
    XCTAssertEqual(nlItems.count, 2)
  }

  func testI18NDirectoryStyleOutputPaths() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in [
      "en/articles/hello.md",
      "nl/articles/hello.md",
    ] }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en", style: .directory)
      .register(
        folder: "articles",
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: [:])],
        writers: [
          .itemWriter { context in context.item.body },
        ]
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }

    // Default locale (en) at root, nl prefixed
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/articles/hello/index.html" }))
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/nl/articles/hello/index.html" }))
  }

  func testI18NDirectoryStyleDefaultLocaleInSubdir() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in [
      "en/articles/hello.md",
      "nl/articles/hello.md",
    ] }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en", style: .directory, defaultLocaleInSubdir: true)
      .register(
        folder: "articles",
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: [:])],
        writers: [
          .itemWriter { context in context.item.body },
        ]
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }

    // Both locales prefixed
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/en/articles/hello/index.html" }))
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/nl/articles/hello/index.html" }))
  }

  func testI18NTranslationLinking() async throws {
    var mock = FileIO.mock
    mock.findFiles = { _ in [
      "en/articles/hello.md",
      "en/articles/world.md",
      "nl/articles/hello.md",
    ] }
    mock.write = { _, _ in }

    let saga = try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en", style: .directory)
      .register(
        folder: "articles",
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: [:])],
        writers: []
      )
      .run()

    // hello.md has translations in both directions
    let enHello = saga.allItems.first { $0.locale == "en" && $0.relativeSource.string.contains("hello") }!
    let nlHello = saga.allItems.first { $0.locale == "nl" && $0.relativeSource.string.contains("hello") }!

    XCTAssertEqual(enHello.translations.count, 1)
    XCTAssertEqual(enHello.translations["nl"]?.url, nlHello.url)
    XCTAssertEqual(nlHello.translations.count, 1)
    XCTAssertEqual(nlHello.translations["en"]?.url, enHello.url)

    // world.md has no Dutch translation
    let enWorld = saga.allItems.first { $0.locale == "en" && $0.relativeSource.string.contains("world") }!
    XCTAssertEqual(enWorld.translations.count, 0)
  }

  func testI18NPerLocaleListWriter() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in [
      "en/articles/one.md",
      "en/articles/two.md",
      "nl/articles/one.md",
    ] }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en", style: .directory)
      .register(
        folder: "articles",
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: [:])],
        writers: [
          .listWriter({ context in "\(context.items.count)" }, output: "index.html"),
        ]
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }

    // English list at root with 2 items
    let enList = finalWrittenPages.first { $0.destination == "root/output/articles/index.html" }
    XCTAssertNotNil(enList)
    XCTAssertEqual(enList?.content, "2")

    // Dutch list prefixed with 1 item
    let nlList = finalWrittenPages.first { $0.destination == "root/output/nl/articles/index.html" }
    XCTAssertNotNil(nlList)
    XCTAssertEqual(nlList?.content, "1")
  }

  func testI18NLocaleInRenderingContext() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in [
      "en/hello.md",
      "nl/hello.md",
    ] }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en", style: .directory)
      .register(
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: [:])],
        writers: [
          .itemWriter { context in context.locale ?? "none" },
        ]
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }

    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/hello/index.html", content: "en")))
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/nl/hello/index.html", content: "nl")))
  }

  func testI18NPrevNextLocaleScoped() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in [
      "en/articles/a.md",
      "en/articles/b.md",
      "nl/articles/a.md",
    ] }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en", style: .directory)
      .register(
        folder: "articles",
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: [:])],
        writers: [
          .itemWriter { context in
            let prev = context.previous?.title ?? "none"
            let next = context.next?.title ?? "none"
            return "prev:\(prev)|next:\(next)"
          },
        ]
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }

    // Dutch article has no prev/next (only 1 article in nl)
    let nlPage = finalWrittenPages.first { $0.destination == "root/output/nl/articles/a/index.html" }
    XCTAssertNotNil(nlPage)
    XCTAssertEqual(nlPage?.content, "prev:none|next:none")
  }

  func testI18NFilenameStyle() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in [
      "articles/hello.en.md",
      "articles/hello.nl.md",
      "articles/world.en.md",
    ] }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    let saga = try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en", style: .filename)
      .register(
        folder: "articles",
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: [:])],
        writers: [
          .itemWriter { context in context.item.body },
        ]
      )
      .run()

    // Locale tagging
    let enItems = saga.allItems.filter { $0.locale == "en" }
    let nlItems = saga.allItems.filter { $0.locale == "nl" }
    XCTAssertEqual(enItems.count, 2)
    XCTAssertEqual(nlItems.count, 1)

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }

    // Default locale at root, locale suffix stripped from filename
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/articles/hello/index.html" }))
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/articles/world/index.html" }))
    // Non-default locale prefixed
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/nl/articles/hello/index.html" }))

    // Translation linking
    let enHello = saga.allItems.first { $0.locale == "en" && $0.relativeSource.string.contains("hello") }!
    XCTAssertEqual(enHello.translations.count, 1)
    XCTAssertNotNil(enHello.translations["nl"])
  }

  func testI18NSlugFrontmatter() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in [
      "about.md",
    ] }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: ["slug": "over-ons"])],
        writers: [
          .itemWriter { context in context.item.body },
        ]
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }

    // Slug overrides the output path
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/over-ons/index.html" }))
    // Original filename path should NOT exist
    XCTAssertFalse(finalWrittenPages.contains(where: { $0.destination == "root/output/about/index.html" }))
  }

  func testI18NRedirectDefaultLocaleAtRoot() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in [
      "en/articles/hello.md",
      "nl/articles/hello.md",
      "en/index.md",
      "nl/index.md",
    ] }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en", style: .directory)
      .register(
        folder: "articles",
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: [:])],
        writers: [
          .itemWriter { context in context.item.body },
          .listWriter({ _ in "" }),
        ]
      )
      .register(
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: [:])],
        writers: [
          .itemWriter { context in context.item.body },
        ]
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }

    // Every default-locale page should have a redirect at /en/...
    let enIndex = finalWrittenPages.first { $0.destination == "root/output/en/index.html" }
    XCTAssertNotNil(enIndex, "Should have redirect at /en/")
    XCTAssertTrue(enIndex!.content.contains("http-equiv=\"refresh\""))
    XCTAssertTrue(enIndex!.content.contains("url=/"))

    let enArticle = finalWrittenPages.first { $0.destination == "root/output/en/articles/hello/index.html" }
    XCTAssertNotNil(enArticle, "Should have redirect at /en/articles/hello/")
    XCTAssertTrue(enArticle!.content.contains("url=/articles/hello/"))

    let enArticlesList = finalWrittenPages.first { $0.destination == "root/output/en/articles/index.html" }
    XCTAssertNotNil(enArticlesList, "Should have redirect at /en/articles/")
    XCTAssertTrue(enArticlesList!.content.contains("url=/articles/"))
  }

  func testI18NTagWriterPerLocale() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in [
      "en/articles/one.md",
      "en/articles/two.md",
      "nl/articles/one.md",
    ] }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en", style: .directory)
      .register(
        folder: "articles",
        metadata: TaggedMetadata.self,
        readers: [.mock(frontmatter: ["tags": "swift"])],
        writers: [
          .tagWriter({ context in "\(context.items.count)" }, tags: \.metadata.tags),
        ]
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }

    // English tag page at root
    let enTag = finalWrittenPages.first { $0.destination == "root/output/articles/tag/swift/index.html" }
    XCTAssertNotNil(enTag)
    XCTAssertEqual(enTag?.content, "2")

    // Dutch tag page prefixed
    let nlTag = finalWrittenPages.first { $0.destination == "root/output/nl/articles/tag/swift/index.html" }
    XCTAssertNotNil(nlTag)
    XCTAssertEqual(nlTag?.content, "1")
  }

  func testI18NNestedDirectoryStyle() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in [
      "en/photos/cats/index.md",
      "en/photos/cats/whiskers.jpg",
      "en/photos/cats/mittens.jpg",
      "en/photos/dogs/index.md",
      "en/photos/dogs/rex.jpg",
      "nl/photos/cats/index.md",
      "nl/photos/cats/whiskers.jpg",
      "nl/photos/dogs/index.md",
      "nl/photos/dogs/rex.jpg",
    ] }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    struct AlbumMetadata: Metadata {}
    struct PhotoMetadata: Metadata {}

    let saga = try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en", style: .directory)
      .register(
        folder: "photos",
        metadata: AlbumMetadata.self,
        readers: [.mock(frontmatter: [:])],
        writers: [
          .listWriter({ context in
            "albums:\(context.items.count)|locale:\(context.locale ?? "none")"
          }),
          .itemWriter { context in
            "album:\(context.item.title)|photos:\(context.item.children.count)|locale:\(context.locale ?? "none")"
          },
        ],
        nested: { nested in
          nested.register(
            metadata: PhotoMetadata.self,
            readers: [.mockImage],
            writers: [
              .itemWriter { context in
                "photo:\(context.item.title)|locale:\(context.locale ?? "none")"
              },
            ]
          )
        }
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }

    // === Locale tagging ===
    let enItems = saga.allItems.filter { $0.locale == "en" }
    let nlItems = saga.allItems.filter { $0.locale == "nl" }
    XCTAssertTrue(enItems.count > 0, "Should have English items")
    XCTAssertTrue(nlItems.count > 0, "Should have Dutch items")

    // === Album list pages (per locale) ===
    let enAlbumList = finalWrittenPages.first { $0.destination == "root/output/photos/index.html" }
    XCTAssertNotNil(enAlbumList, "English album list should be at root (default locale)")
    XCTAssertEqual(enAlbumList?.content, "albums:2|locale:en")

    let nlAlbumList = finalWrittenPages.first { $0.destination == "root/output/nl/photos/index.html" }
    XCTAssertNotNil(nlAlbumList, "Dutch album list should be under nl/")
    XCTAssertEqual(nlAlbumList?.content, "albums:2|locale:nl")

    // === Album detail pages ===
    // English albums at root
    let enCatsAlbum = finalWrittenPages.first { $0.destination == "root/output/photos/cats/index.html" }
    XCTAssertNotNil(enCatsAlbum)
    XCTAssertTrue(enCatsAlbum!.content.contains("photos:2"), "English cats album should have 2 photos")
    XCTAssertTrue(enCatsAlbum!.content.contains("locale:en"))

    // Dutch albums under nl/
    let nlCatsAlbum = finalWrittenPages.first { $0.destination == "root/output/nl/photos/cats/index.html" }
    XCTAssertNotNil(nlCatsAlbum)
    XCTAssertTrue(nlCatsAlbum!.content.contains("photos:1"), "Dutch cats album should have 1 photo (whiskers only)")
    XCTAssertTrue(nlCatsAlbum!.content.contains("locale:nl"))

    // === Photo detail pages ===
    // English photo at root
    XCTAssertTrue(finalWrittenPages.contains(where: {
      $0.destination == "root/output/photos/cats/whiskers/index.html" && $0.content.contains("locale:en")
    }), "English whiskers photo should be at root")

    // Dutch photo under nl/
    XCTAssertTrue(finalWrittenPages.contains(where: {
      $0.destination == "root/output/nl/photos/cats/whiskers/index.html" && $0.content.contains("locale:nl")
    }), "Dutch whiskers photo should be under nl/")

    // === No cross-locale leakage ===
    // English mittens photo should exist
    XCTAssertTrue(finalWrittenPages.contains(where: {
      $0.destination == "root/output/photos/cats/mittens/index.html"
    }), "English mittens photo should exist")

    // Dutch mittens photo should NOT exist (not in nl/ content)
    XCTAssertFalse(finalWrittenPages.contains(where: {
      $0.destination == "root/output/nl/photos/cats/mittens/index.html"
    }), "Dutch mittens photo should NOT exist")
  }

  func testI18NSitemapHreflang() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in [
      "en/articles/hello.md",
      "nl/articles/hello.md",
      "en/articles/only-english.md",
    ] }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en", style: .directory)
      .register(
        folder: "articles",
        metadata: TaggedMetadata.self,
        readers: [.mock(frontmatter: ["tags": "swift"])],
        writers: [
          .itemWriter { context in context.item.body },
          .listWriter({ _ in "" }),
          .tagWriter({ _ in "" }, tags: \.metadata.tags),
        ]
      )
      .createPage("sitemap.xml", using: sitemap(baseURL: try XCTUnwrap(URL(string: "https://example.com"))))
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }
    let sitemapPage = try XCTUnwrap(finalWrittenPages.first { $0.destination == "root/output/sitemap.xml" })
    let content = sitemapPage.content

    // Should have xhtml namespace
    XCTAssertTrue(content.contains("xmlns:xhtml="))

    // Item pages: hello has translations — both entries should have hreflang
    XCTAssertTrue(content.contains("hreflang=\"en\" href=\"https://example.com/articles/hello/\""))
    XCTAssertTrue(content.contains("hreflang=\"nl\" href=\"https://example.com/nl/articles/hello/\""))

    // only-english has no translations — plain <url> without hreflang
    XCTAssertTrue(content.contains("<loc>https://example.com/articles/only-english/</loc>"))
    XCTAssertFalse(content.contains("hreflang=\"en\" href=\"https://example.com/articles/only-english/\""))

    // List pages: articles/index.html and nl/articles/index.html should be linked
    XCTAssertTrue(content.contains("hreflang=\"en\" href=\"https://example.com/articles/\""))
    XCTAssertTrue(content.contains("hreflang=\"nl\" href=\"https://example.com/nl/articles/\""))

    // Tag pages: articles/tag/swift/ and nl/articles/tag/swift/ should be linked
    XCTAssertTrue(content.contains("hreflang=\"en\" href=\"https://example.com/articles/tag/swift/\""))
    XCTAssertTrue(content.contains("hreflang=\"nl\" href=\"https://example.com/nl/articles/tag/swift/\""))
  }

  func testI18NSlugWithTranslationLinking() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in [
      "en/about.md",
      "nl/about.md",
    ] }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    // English about has no slug, Dutch about has slug "over-ons"
    let saga = try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en", style: .directory)
      .register(
        metadata: EmptyMetadata.self,
        readers: [
          Reader(supportedExtensions: ["md"]) { absoluteSource in
            let isNl = absoluteSource.string.contains("nl/")
            return (title: "Test", body: "<p>\(absoluteSource)</p>", frontmatter: isNl ? ["slug": "over-ons"] : [:])
          }
        ],
        writers: [
          .itemWriter { context in context.item.url },
        ]
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }

    // English about at root with default path
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/about/index.html" }))

    // Dutch about with slug override
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/nl/over-ons/index.html" }))

    // Translations should still be linked (matching by source filename, not output path)
    let enAbout = saga.allItems.first { $0.locale == "en" }!
    let nlAbout = saga.allItems.first { $0.locale == "nl" }!
    XCTAssertEqual(enAbout.translations.count, 1)
    XCTAssertEqual(enAbout.translations["nl"]?.url, nlAbout.url)
    XCTAssertEqual(nlAbout.url, "/nl/over-ons/")
  }

  func testI18NFilenameStyleListWriter() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in [
      "articles/one.en.md",
      "articles/two.en.md",
      "articles/one.nl.md",
    ] }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en", style: .filename)
      .register(
        folder: "articles",
        metadata: TaggedMetadata.self,
        readers: [.mock(frontmatter: ["tags": "swift"])],
        writers: [
          .listWriter({ context in "count:\(context.items.count)|locale:\(context.locale ?? "none")" }),
          .tagWriter({ context in "tag:\(context.key)|count:\(context.items.count)" }, tags: \.metadata.tags),
        ]
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }

    // English list at root with 2 items
    let enList = finalWrittenPages.first { $0.destination == "root/output/articles/index.html" }
    XCTAssertNotNil(enList)
    XCTAssertEqual(enList?.content, "count:2|locale:en")

    // Dutch list prefixed with 1 item
    let nlList = finalWrittenPages.first { $0.destination == "root/output/nl/articles/index.html" }
    XCTAssertNotNil(nlList)
    XCTAssertEqual(nlList?.content, "count:1|locale:nl")

    // Tag pages per locale
    let enTag = finalWrittenPages.first { $0.destination == "root/output/articles/tag/swift/index.html" }
    XCTAssertNotNil(enTag)
    XCTAssertEqual(enTag?.content, "tag:swift|count:2")

    let nlTag = finalWrittenPages.first { $0.destination == "root/output/nl/articles/tag/swift/index.html" }
    XCTAssertNotNil(nlTag)
    XCTAssertEqual(nlTag?.content, "tag:swift|count:1")
  }

  static let allTests = [
    ("testInitializer", testInitializer),
    ("testRegister", testRegister),
    ("testMakeSureEmptyPathHasNoComponents", testMakeSureEmptyPathHasNoComponents),
    ("testReaderAndItemWriterAndListWriter", testReaderAndItemWriterAndListWriter),
    ("testItemWriterPreviousNext", testItemWriterPreviousNext),
    ("testCustomSorting", testCustomSorting),
    ("testYearWriter", testYearWriter),
    ("testTagWriter", testTagWriter),
    ("testStaticFiles", testStaticFiles),
    ("testWriteMode", testWriteMode),
    ("testFilterItems", testFilterItems),
    ("testFilterButNotHandledItems", testFilterButNotHandledItems),
    ("testDateFromFrontMatter", testDateFromFrontMatter),
    ("testFolderGlob", testFolderGlob),
    ("testNestedSimple", testNestedSimple),
    ("testNestedWithOuterWriters", testNestedWithOuterWriters),
    ("testNestedDifferentReaders", testNestedDifferentReaders),
    ("testNestedChildrenAccessor", testNestedChildrenAccessor),
    ("testNestedInNested", testNestedInNested),
    ("testNestedInNestedWithDifferentMetadata", testNestedInNestedWithDifferentMetadata),
    ("testSubfolderIsNilWithoutNesting", testSubfolderIsNilWithoutNesting),
    ("testMetadataDecoder", testMetadataDecoder),
    ("testSlugified", testSlugified),
    ("testRegisterFetch", testRegisterFetch),
    ("testRegisterFetchWithFileBasedItems", testRegisterFetchWithFileBasedItems),
    ("testCreatePage", testCreatePage),
    ("testCreatePageOutputPath", testCreatePageOutputPath),
    ("testHash", testHash),
    ("testHashWithoutLeadingSlash", testHashWithoutLeadingSlash),
    ("testHashUnknownFile", testHashUnknownFile),
    ("testPostProcess", testPostProcess),
    ("testPostProcessWithCreatePage", testPostProcessWithCreatePage),
    ("testPostProcessReceivesRelativePath", testPostProcessReceivesRelativePath),
    ("testGeneratedPages", testGeneratedPages),
    ("testSitemap", testSitemap),
    ("testI18NDirectoryStyleLocaleTagging", testI18NDirectoryStyleLocaleTagging),
    ("testI18NDirectoryStyleOutputPaths", testI18NDirectoryStyleOutputPaths),
    ("testI18NDirectoryStyleDefaultLocaleInSubdir", testI18NDirectoryStyleDefaultLocaleInSubdir),
    ("testI18NTranslationLinking", testI18NTranslationLinking),
    ("testI18NPerLocaleListWriter", testI18NPerLocaleListWriter),
    ("testI18NLocaleInRenderingContext", testI18NLocaleInRenderingContext),
    ("testI18NPrevNextLocaleScoped", testI18NPrevNextLocaleScoped),
    ("testI18NFilenameStyle", testI18NFilenameStyle),
    ("testI18NSlugFrontmatter", testI18NSlugFrontmatter),
    ("testI18NRedirectDefaultLocaleAtRoot", testI18NRedirectDefaultLocaleAtRoot),
    ("testI18NTagWriterPerLocale", testI18NTagWriterPerLocale),
    ("testI18NNestedDirectoryStyle", testI18NNestedDirectoryStyle),
    ("testI18NSitemapHreflang", testI18NSitemapHreflang),
    ("testI18NSlugWithTranslationLinking", testI18NSlugWithTranslationLinking),
    ("testI18NFilenameStyleListWriter", testI18NFilenameStyleListWriter),
  ]
}
