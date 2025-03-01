import XCTest
import PathKit
@testable import Saga

extension FileIO {
  static var mock = Self(
    resolveSwiftPackageFolder: { _ in "root" },
    findFiles: { _ in ["test.md", "test2.md", "style.css"] },
    deletePath: { _ in },
    write: { _, _ in },
    mkpath: { _ in },
    copy: { _, _ in }
  )
}

extension Reader {
  static func mock(frontmatter: [String: String]) -> Self {
    return Self(supportedExtensions: ["md"]) { absoluteSource in
      return (title: "Test", body: "<p>\(absoluteSource)</p>", frontmatter: frontmatter)
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
    var writtenPages: [WrittenPage] = []
    var deletePathCalled = false

    var mock = FileIO.mock
    mock.write = { destination, content in
      writtenPages.append(.init(destination: destination, content: content))
    }
    mock.deletePath = { _ in
      deletePathCalled = true
    }

    let saga = try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        metadata: EmptyMetadata.self,
        readers: [
          .mock(frontmatter: [:])
        ],
        writers: [
          .itemWriter { context in context.item.body },
          .listWriter({ context in context.items.map(\.body).joined(separator: "") }, output: "list.html")
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
    XCTAssertEqual(writtenPages.count, 3)
    XCTAssertEqual(writtenPages[0].destination, "root/output/test2/index.html")
    XCTAssertEqual(writtenPages[0].content, "<p>test2.md</p>")
    XCTAssertEqual(writtenPages[1].destination, "root/output/test/index.html")
    XCTAssertEqual(writtenPages[1].content, "<p>test.md</p>")
    XCTAssertEqual(writtenPages[2].destination, "root/output/list.html")
    XCTAssertEqual(writtenPages[2].content, "<p>test2.md</p><p>test.md</p>")
  }
  
  // If the frontmatter contains a date property then this should be set to the item's date
  func testDateFromFrontMatter() async throws {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"

    let saga = try await Saga(input: "input", output: "output", fileIO: FileIO.mock)
      .register(
        metadata: EmptyMetadata.self,
        readers: [
          .mock(frontmatter: ["date": "2025-01-02"])
        ],
        writers: []
      )
      .run()
    
    XCTAssertEqual(saga.fileStorage[0].item?.date, formatter.date(from: "2025-01-02"))
  }

  func testYearWriter() async throws {
    var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.write = { destination, content in
      writtenPages.append(.init(destination: destination, content: content))
    }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        metadata: EmptyMetadata.self,
        readers: [
          .mock(frontmatter: [:])
        ],
        writers: [
          .yearWriter({ context in context.items.map(\.body).joined(separator: "") })
        ]
      )
      .run()
    
    let currentYear = Calendar.current.component(.year, from: Date())

    XCTAssertEqual(writtenPages.count, 1)
    XCTAssertEqual(writtenPages, [
      WrittenPage(destination: Path("root/output/\(currentYear)/index.html"), content: "<p>test2.md</p><p>test.md</p>"),
    ])
  }

  func testTagWriter() async throws {
    var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.write = { destination, content in
      writtenPages.append(.init(destination: destination, content: content))
    }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        metadata: TaggedMetadata.self,
        readers: [
          .mock(frontmatter: ["tags": "one, with space"])
        ],
        writers: [
          .tagWriter({ context in context.items.map(\.body).joined(separator: "") }, tags: \.metadata.tags)
        ]
      )
      .run()

    XCTAssertEqual(writtenPages.count, 2)
    XCTAssertEqual(writtenPages, [
      WrittenPage(destination: "root/output/tag/one/index.html", content: "<p>test2.md</p><p>test.md</p>"),
      WrittenPage(destination: "root/output/tag/with-space/index.html", content: "<p>test2.md</p><p>test.md</p>"),
    ])
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
          .mock(frontmatter: ["tags": "one, with space"])
        ],
        writers: [
        ]
      )
      .run()
      .staticFiles()

    XCTAssertEqual(writtenFiles, ["root/output/style.css"])
  }

  func testWriteMode() async throws {
    var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.write = { destination, content in
      writtenPages.append(.init(destination: destination, content: content))
    }

    let saga = try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        metadata: EmptyMetadata.self,
        readers: [
          .mock(frontmatter: [:])
        ],
        itemWriteMode: .keepAsFile,
        writers: [
          .itemWriter { context in context.item.body },
        ]
      )
      .run()

    XCTAssertEqual(saga.fileStorage[0].item?.relativeDestination, "test.html")
    XCTAssertEqual(saga.fileStorage[1].item?.relativeDestination, "test2.html")
    XCTAssertEqual(writtenPages[0].destination, "root/output/test2.html")
    XCTAssertEqual(writtenPages[1].destination, "root/output/test.html")
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
      "url": "https://www.example.com"
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
