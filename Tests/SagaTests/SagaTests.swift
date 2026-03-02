import PathKit
@testable import Saga
import XCTest

extension FileIO {
  static var mock = Self(
    resolveSwiftPackageFolder: { _ in "root" },
    findFiles: { _ in ["test.md", "test2.md", "style.css"] },
    deletePath: { _ in },
    write: { _, _ in },
    mkpath: { _ in },
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
}

struct TaggedMetadata: Metadata {
  let tags: [String]
}

struct WrittenPage: Equatable {
  let destination: Path
  let content: String
}

final class SagaTests: XCTestCase {
  func testInitializer() throws {
    var deletePathCalled = false

    var mock = FileIO.mock
    mock.deletePath = { _ in
      deletePathCalled = true
    }

    let saga = try Saga(input: "input", output: "output", fileIO: mock)
    XCTAssertEqual(saga.rootPath, "root")
    XCTAssertEqual(saga.inputPath, "root/input")
    XCTAssertEqual(saga.outputPath, "root/output")
    XCTAssertEqual(saga.fileStorage.count, 3)
    XCTAssertEqual(saga.fileStorage[0].path, "test.md")
    XCTAssertNil(saga.fileStorage[0]._item)
    XCTAssertEqual(saga.fileStorage[1].path, "test2.md")
    XCTAssertNil(saga.fileStorage[1]._item)
    XCTAssertEqual(saga.fileStorage[2].path, "style.css")
    XCTAssertNil(saga.fileStorage[2]._item)
    XCTAssertEqual(saga.allItems.count, 0)
    XCTAssertEqual(deletePathCalled, false)
  }

  func testRegister() throws {
    let saga = try Saga(input: "input", output: "output", fileIO: .mock)
    XCTAssertEqual(saga.processSteps.count, 0)

    try saga.register(metadata: EmptyMetadata.self, readers: [], writers: [])
    XCTAssertEqual(saga.processSteps.count, 1)
  }

  func testReaderAndItemWriterAndListWriter() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    var writtenPages: [WrittenPage] = []
    var deletePathCalled = false

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

    // FileStorage still tracks handled state
    XCTAssertEqual(saga.fileStorage.count, 3)
    XCTAssertEqual(saga.fileStorage[0].path, "test.md")
    XCTAssertNotNil(saga.fileStorage[0]._item)
    XCTAssertEqual(saga.fileStorage[1].path, "test2.md")
    XCTAssertNotNil(saga.fileStorage[1]._item)
    XCTAssertEqual(saga.fileStorage[2].path, "style.css")
    XCTAssertNil(saga.fileStorage[2]._item)

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
    var writtenPages: [WrittenPage] = []

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

    // The readers turn Markdown files into Items and store them in the fileStorage
    XCTAssertEqual(saga.fileStorage.count, 3)

    // And when the writer runs, the Items get written to disk
    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }
    XCTAssertEqual(finalWrittenPages.count, 2)
    XCTAssertEqual(finalWrittenPages, [WrittenPage(destination: "root/output/list.html", content: ""), WrittenPage(destination: "root/output/list.html", content: "")])
  }

  func testFilterButNotHandledItems() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    var writtenPages: [WrittenPage] = []

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

    // The readers turn Markdown files into Items and store them in the fileStorage
    XCTAssertEqual(saga.fileStorage.count, 3)

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
    var writtenPages: [WrittenPage] = []

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
    var writtenPages: [WrittenPage] = []

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
    var writtenFiles: [Path] = []

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
    var writtenPages: [WrittenPage] = []

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
    var writtenPages: [WrittenPage] = []

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
    var writtenPages: [WrittenPage] = []

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
    var writtenPages: [WrittenPage] = []

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
    // Both a.md and b.md have same date from mock, so their order depends on deterministic index ordering
    // a.md comes before b.md by index, but sorted by date descending they keep index order when dates are equal
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
    var writtenPages: [WrittenPage] = []

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
    var writtenPages: [WrittenPage] = []

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
    var writtenPages: [WrittenPage] = []

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
    var writtenPages: [WrittenPage] = []

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

  func testPostProcess() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    var writtenPages: [WrittenPage] = []

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
    var writtenPages: [WrittenPage] = []

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
    var receivedPaths: [Path] = []

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

  static var allTests = [
    ("testInitializer", testInitializer),
    ("testRegister", testRegister),
    ("testReaderAndItemWriterAndListWriter", testReaderAndItemWriterAndListWriter),
    ("testYearWriter", testYearWriter),
    ("testTagWriter", testTagWriter),
    ("testWriteMode", testWriteMode),
    ("testSlugified", testSlugified),
    ("testRegisterFetch", testRegisterFetch),
    ("testRegisterFetchWithFileBasedItems", testRegisterFetchWithFileBasedItems),
  ]
}
