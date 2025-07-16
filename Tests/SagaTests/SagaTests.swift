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
    XCTAssertNil(saga.fileStorage[0].item)
    XCTAssertEqual(saga.fileStorage[1].path, "test2.md")
    XCTAssertNil(saga.fileStorage[1].item)
    XCTAssertEqual(saga.fileStorage[2].path, "style.css")
    XCTAssertNil(saga.fileStorage[2].item)
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

    // The readers turn Markdown files into Items and store them in the fileStorage
    XCTAssertEqual(saga.fileStorage.count, 3)
    XCTAssertEqual(saga.fileStorage[0].path, "test.md")
    XCTAssertEqual(saga.fileStorage[0].item?.body, "<p>test.md</p>")
    XCTAssertEqual(saga.fileStorage[1].path, "test2.md")
    XCTAssertEqual(saga.fileStorage[1].item?.body, "<p>test2.md</p>")
    XCTAssertEqual(saga.fileStorage[2].path, "style.css")
    XCTAssertNil(saga.fileStorage[2].item)

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
        filteredOutItemsAreHandled: false,
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
  
  // If the frontmatter contains a date property then this should be set to the item's date
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

    XCTAssertEqual(saga.fileStorage[0].item?.date, formatter.date(from: "2025-01-02"))
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
    var writtenFiles: [Path] = []

    var mock = FileIO.mock
    mock.copy = { origin, destination in
      writtenFiles.append(destination)
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
      .staticFiles()

    XCTAssertEqual(writtenFiles, ["root/output/style.css"])
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
    XCTAssertEqual(saga.fileStorage[0].item?.relativeDestination, "test.html")
    XCTAssertEqual(saga.fileStorage[1].item?.relativeDestination, "test2.html")
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/test.html", content: "<p>test.md</p>")))
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/test2.html", content: "<p>test2.md</p>")))
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
    XCTAssertEqual(decoded.url, URL(string: "https://www.example.com")!)
  }

  func testSlugified() throws {
    XCTAssertEqual("one two".slugified, "one-two")
    XCTAssertEqual("one - two".slugified, "one-two")
    XCTAssertEqual("One Two".slugified, "one-two")
    XCTAssertEqual("One! .Two@".slugified, "one-two")
    XCTAssertEqual("one-two".slugified, "one-two")
    XCTAssertEqual("one_two".slugified, "one_two")
    XCTAssertEqual("ONE-TWO".slugified, "one-two")
  }

  static var allTests = [
    ("testInitializer", testInitializer),
    ("testRegister", testRegister),
    ("testReaderAndItemWriterAndListWriter", testReaderAndItemWriterAndListWriter),
    ("testYearWriter", testYearWriter),
    ("testTagWriter", testTagWriter),
    ("testWriteMode", testWriteMode),
    ("testSlugified", testSlugified),
  ]
}
