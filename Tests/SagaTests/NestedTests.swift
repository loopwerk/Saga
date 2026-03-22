import Foundation
@testable import Saga
import SagaPathKit
import XCTest

final class NestedTests: XCTestCase, @unchecked Sendable {
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
}
