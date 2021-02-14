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
    write: { _, _ in }
  )
}

extension Reader {
  static func mock(metadata: M) -> Self {
    return Self(supportedExtensions: ["md"]) { absoluteSource, relativeSource, relativeDestination in
      return Item(
        relativeSource: relativeSource,
        relativeDestination: relativeDestination,
        title: "Test",
        rawContent: "test",
        body: "<p>\(relativeSource)</p>",
        date: Date(),
        lastModified: Date(),
        metadata: metadata
      )
    }
  }
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

  func testItemWriterRun() throws {
    struct WrittenPage: Equatable {
      let destination: Path
      let content: String
    }

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

  static var allTests = [
    ("testInitializer", testInitializer),
    ("testRegister", testRegister),
    ("testItemWriterRun", testItemWriterRun),
  ]
}
