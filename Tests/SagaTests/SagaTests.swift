import XCTest
import PathKit
@testable import Saga

private struct TestMetadata: Metadata {
  let property: String
}

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
  static func mock(metadata: M) -> Self {
    return Self(supportedExtensions: ["md"]) { absoluteSource, relativeSource, relativeDestination in
      if relativeSource == "test.md" {
        return Item(
          relativeSource: relativeSource,
          relativeDestination: relativeDestination,
          title: "Test",
          rawContent: "test",
          body: "<p>\(relativeSource)</p>",
          date: Date(timeIntervalSince1970: 1580598000),
          lastModified: Date(timeIntervalSince1970: 1580598000),
          metadata: metadata
        )
      } else {
        return Item(
          relativeSource: relativeSource,
          relativeDestination: relativeDestination,
          title: "Test",
          rawContent: "test",
          body: "<p>\(relativeSource)</p>",
          date: Date(timeIntervalSince1970: 1612220400),
          lastModified: Date(timeIntervalSince1970: 1612220400),
          metadata: metadata
        )
      }
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

    let saga = try Saga(input: "input", output: "output", siteMetadata: TestMetadata(property: "test"), fileIO: mock)
    XCTAssertEqual(saga.siteMetadata.property, "test")

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
    XCTAssertEqual(deletePathCalled, true)
  }

  func testRegister() throws {
    let saga = try Saga(input: "input", output: "output", siteMetadata: TestMetadata(property: "test"), fileIO: .mock)
    XCTAssertEqual(saga.processSteps.count, 0)

    try saga.register(metadata: EmptyMetadata.self, readers: [], writers: [])
    XCTAssertEqual(saga.processSteps.count, 1)
  }

  func testReaderAndItemWriterAndListWriter() throws {
    var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.write = { destination, content in
      writtenPages.append(.init(destination: destination, content: content))
    }

    let saga = try Saga(input: "input", output: "output", siteMetadata: TestMetadata(property: "test"), fileIO: mock)
      .register(
        metadata: EmptyMetadata.self,
        readers: [
          .mock(metadata: EmptyMetadata())
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

    // And when the writer runs, the Items get written to disk
    XCTAssertEqual(writtenPages.count, 3)
    XCTAssertEqual(writtenPages[0].destination, "root/output/test2/index.html")
    XCTAssertEqual(writtenPages[0].content, "<p>test2.md</p>")
    XCTAssertEqual(writtenPages[1].destination, "root/output/test/index.html")
    XCTAssertEqual(writtenPages[1].content, "<p>test.md</p>")
    XCTAssertEqual(writtenPages[2].destination, "root/output/list.html")
    XCTAssertEqual(writtenPages[2].content, "<p>test2.md</p><p>test.md</p>")
  }

  func testYearWriter() throws {
    var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.write = { destination, content in
      writtenPages.append(.init(destination: destination, content: content))
    }

    try Saga(input: "input", output: "output", siteMetadata: TestMetadata(property: "test"), fileIO: mock)
      .register(
        metadata: EmptyMetadata.self,
        readers: [
          .mock(metadata: EmptyMetadata())
        ],
        writers: [
          .yearWriter({ context in context.items.map(\.body).joined(separator: "") })
        ]
      )
      .run()

    XCTAssertEqual(writtenPages.count, 2)
    XCTAssertEqual(writtenPages, [
      WrittenPage(destination: "root/output/2020/index.html", content: "<p>test.md</p>"),
      WrittenPage(destination: "root/output/2021/index.html", content: "<p>test2.md</p>"),
    ])
  }

  func testTagWriter() throws {
    var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.write = { destination, content in
      writtenPages.append(.init(destination: destination, content: content))
    }

    try Saga(input: "input", output: "output", siteMetadata: TestMetadata(property: "test"), fileIO: mock)
      .register(
        metadata: TaggedMetadata.self,
        readers: [
          .mock(metadata: TaggedMetadata(tags: ["one", "with space"]))
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

  func testStaticFiles() throws {
    var writtenFiles: [Path] = []

    var mock = FileIO.mock
    mock.copy = { origin, destination in
      writtenFiles.append(destination)
    }

    try Saga(input: "input", output: "output", siteMetadata: TestMetadata(property: "test"), fileIO: mock)
      .register(
        metadata: TaggedMetadata.self,
        readers: [
          .mock(metadata: TaggedMetadata(tags: ["one", "with space"]))
        ],
        writers: [
        ]
      )
      .run()
      .staticFiles()

    XCTAssertEqual(writtenFiles, ["root/output/style.css"])
  }

  static var allTests = [
    ("testInitializer", testInitializer),
    ("testRegister", testRegister),
    ("testReaderAndItemWriterAndListWriter", testReaderAndItemWriterAndListWriter),
    ("testYearWriter", testYearWriter),
    ("testTagWriter", testTagWriter),
  ]
}
