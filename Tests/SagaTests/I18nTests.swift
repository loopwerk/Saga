import Foundation
@testable import Saga
import SagaPathKit
import XCTest

final class I18nTests: XCTestCase, @unchecked Sendable {
  func testI18nBasic() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in
      [
        "en/articles/hello.md",
        "nl/articles/hello.md",
        "en/articles/world.md",
        "nl/articles/world.md",
      ]
    }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    let saga = try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en")
      .register(
        folder: "articles",
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: ["date": "2025-01-01"])],
        writers: [
          .itemWriter { context in "\(context.locale ?? "nil"):\(context.item.body)" },
        ]
      )
      .run()

    XCTAssertEqual(saga.allItems.count, 4)

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }
    XCTAssertEqual(finalWrittenPages.count, 4)

    // Default locale (en) writes to root (no locale prefix)
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/articles/hello/index.html" }))
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/articles/world/index.html" }))

    // Non-default locale (nl) gets a locale prefix
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/nl/articles/hello/index.html" }))
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/nl/articles/world/index.html" }))
  }

  func testI18nLocalizedOutputFolder() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in
      [
        "en/articles/hello.md",
        "nl/articles/hello.md",
      ]
    }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en", localizedOutputFolders: ["articles": ["nl": "artikelen"]])
      .register(
        folder: "articles",
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: ["date": "2025-01-01"])],
        writers: [
          .itemWriter { context in context.item.body },
        ]
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }
    XCTAssertEqual(finalWrittenPages.count, 2)

    // English: articles (unchanged)
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/articles/hello/index.html" }))

    // Dutch: artikelen (localized folder name)
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/nl/artikelen/hello/index.html" }))
  }

  func testI18nDefaultLocaleInSubdir() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in
      [
        "en/articles/hello.md",
        "nl/articles/hello.md",
      ]
    }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en", prefixDefaultLocaleOutputFolder: true)
      .register(
        folder: "articles",
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: ["date": "2025-01-01"])],
        writers: [
          .itemWriter { context in context.item.body },
        ]
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }
    XCTAssertEqual(finalWrittenPages.count, 2)

    // Both locales get a prefix
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/en/articles/hello/index.html" }))
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/nl/articles/hello/index.html" }))
  }

  func testI18nTranslationLinking() async throws {
    var mock = FileIO.mock
    mock.findFiles = { _ in
      [
        "en/articles/hello.md",
        "nl/articles/hello.md",
        "en/articles/world.md",
      ]
    }

    let saga = try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en")
      .register(
        folder: "articles",
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: ["date": "2025-01-01"])],
        writers: []
      )
      .run()

    XCTAssertEqual(saga.allItems.count, 3)

    // Find the English and Dutch hello items
    let enHello = saga.allItems.first { $0.locale == "en" && $0.relativeSource.string.contains("hello") }
    let nlHello = saga.allItems.first { $0.locale == "nl" && $0.relativeSource.string.contains("hello") }
    let enWorld = saga.allItems.first { $0.locale == "en" && $0.relativeSource.string.contains("world") }

    XCTAssertNotNil(enHello)
    XCTAssertNotNil(nlHello)
    XCTAssertNotNil(enWorld)

    // hello has translations in both directions
    XCTAssertEqual(enHello?.translations.count, 1)
    XCTAssertTrue(enHello?.translations["nl"] === nlHello)
    XCTAssertEqual(nlHello?.translations.count, 1)
    XCTAssertTrue(nlHello?.translations["en"] === enHello)

    // world has no Dutch translation
    XCTAssertEqual(enWorld?.translations.count, 0)
  }

  func testI18nLocaleOnItem() async throws {
    var mock = FileIO.mock
    mock.findFiles = { _ in
      [
        "en/hello.md",
        "nl/hello.md",
      ]
    }

    let saga = try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en")
      .register(
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: ["date": "2025-01-01"])],
        writers: []
      )
      .run()

    let enItem = saga.allItems.first { $0.locale == "en" }
    let nlItem = saga.allItems.first { $0.locale == "nl" }

    XCTAssertNotNil(enItem)
    XCTAssertNotNil(nlItem)
    XCTAssertEqual(enItem?.locale, "en")
    XCTAssertEqual(nlItem?.locale, "nl")
  }

  func testI18nLocaleInRenderingContext() async throws {
    nonisolated(unsafe) var capturedLocales: [String?] = []
    let localesQueue = DispatchQueue(label: "locales", attributes: .concurrent)

    var mock = FileIO.mock
    mock.findFiles = { _ in
      [
        "en/hello.md",
        "nl/hello.md",
      ]
    }
    mock.write = { _, _ in }

    _ = try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en")
      .register(
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: ["date": "2025-01-01"])],
        writers: [
          .itemWriter { context in
            localesQueue.sync(flags: .barrier) {
              capturedLocales.append(context.locale)
            }
            return context.item.body
          },
        ]
      )
      .run()

    let finalLocales = localesQueue.sync { Set(capturedLocales.compactMap(\.self)) }
    XCTAssertEqual(finalLocales, ["en", "nl"])
  }

  func testI18nListWriter() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in
      [
        "en/articles/hello.md",
        "en/articles/world.md",
        "nl/articles/hello.md",
        "nl/articles/world.md",
      ]
    }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    _ = try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en", localizedOutputFolders: ["articles": ["nl": "artikelen"]])
      .register(
        folder: "articles",
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: ["date": "2025-01-01"])],
        writers: [
          .listWriter({ context in "list:\(context.locale ?? "nil")" }, output: "index.html"),
        ]
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }
    XCTAssertEqual(finalWrittenPages.count, 2)

    // English list at articles/index.html
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/articles/index.html", content: "list:en")))

    // Dutch list at nl/artikelen/index.html
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/nl/artikelen/index.html", content: "list:nl")))
  }

  func testI18nTagWriter() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in
      [
        "en/articles/hello.md",
        "nl/articles/hello.md",
      ]
    }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    _ = try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en", localizedOutputFolders: ["articles": ["nl": "artikelen"]])
      .register(
        folder: "articles",
        metadata: TaggedMetadata.self,
        readers: [.mock(frontmatter: ["date": "2025-01-01", "tags": "swift, saga"])],
        writers: [
          .tagWriter({ context in "tag:\(context.key):\(context.locale ?? "nil")" }, tags: \.metadata.tags),
        ]
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }

    // English tags at articles/tag/...
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/articles/tag/swift/index.html" && $0.content == "tag:swift:en" }))
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/articles/tag/saga/index.html" && $0.content == "tag:saga:en" }))

    // Dutch tags at nl/artikelen/tag/...
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/nl/artikelen/tag/swift/index.html" && $0.content == "tag:swift:nl" }))
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/nl/artikelen/tag/saga/index.html" && $0.content == "tag:saga:nl" }))
  }

  func testI18nSitemapWithAlternates() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in
      [
        "en/articles/hello.md",
        "nl/articles/hello.md",
        "en/articles/only-english.md",
      ]
    }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    _ = try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en")
      .register(
        folder: "articles",
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: ["date": "2025-01-01"])],
        writers: [
          .itemWriter { context in context.item.body },
        ]
      )
      .createPage("sitemap.xml", using: Saga.sitemap(baseURL: try XCTUnwrap(URL(string: "https://example.com"))))
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }
    let sitemapPage = finalWrittenPages.first { $0.destination == "root/output/sitemap.xml" }
    XCTAssertNotNil(sitemapPage)

    let sitemap = try XCTUnwrap(sitemapPage?.content)

    // Should have xhtml namespace since there are alternates
    XCTAssertTrue(sitemap.contains("xmlns:xhtml"))

    // The hello page (has both locales) should have alternate links
    XCTAssertTrue(sitemap.contains("hreflang=\"en\" href=\"https://example.com/articles/hello/\""))
    XCTAssertTrue(sitemap.contains("hreflang=\"nl\" href=\"https://example.com/nl/articles/hello/\""))

    // The only-english page should NOT have alternate links
    XCTAssertTrue(sitemap.contains("<loc>https://example.com/articles/only-english/</loc>"))
    // Check it doesn't have an xhtml:link right after it
    let onlyEnglishRange = try XCTUnwrap(sitemap.range(of: "<loc>https://example.com/articles/only-english/</loc>"))
    let afterOnlyEnglish = sitemap[onlyEnglishRange.upperBound...]
    let nextUrl = try XCTUnwrap(afterOnlyEnglish.range(of: "</url>"))
    let between = String(afterOnlyEnglish[..<nextUrl.lowerBound])
    XCTAssertFalse(between.contains("xhtml:link"))
  }

  func testI18nSlugWithLocalizedOutputFolder() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in
      [
        "en/articles/hello.md",
        "nl/articles/hello.md",
      ]
    }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    // The Dutch article has a slug override
    let saga = try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en", localizedOutputFolders: ["articles": ["nl": "artikelen"]])
      .register(
        folder: "articles",
        metadata: EmptyMetadata.self,
        readers: [
          .init(supportedExtensions: ["md"]) { path in
            let isNl = path.string.contains("nl/")
            let frontmatter: [String: String] = isNl
              ? ["date": "2025-01-01", "slug": "hallo"]
              : ["date": "2025-01-01"]
            return (title: "Test", body: "<p>\(path)</p>", frontmatter: frontmatter)
          },
        ],
        writers: [
          .itemWriter { context in context.item.body },
        ]
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }
    XCTAssertEqual(finalWrittenPages.count, 2)

    // English: normal path
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/articles/hello/index.html" }))

    // Dutch: localized folder + slug override
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/nl/artikelen/hallo/index.html" }))

    // Translations should still be linked (same filename across locales)
    let enItem = saga.allItems.first { $0.locale == "en" }
    let nlItem = saga.allItems.first { $0.locale == "nl" }
    XCTAssertTrue(enItem?.translations["nl"] === nlItem)
    XCTAssertTrue(nlItem?.translations["en"] === enItem)
  }

  func testI18nStaticFilesUseLocalizedOutputFolder() async throws {
    nonisolated(unsafe) var copiedFiles: [(from: Path, to: Path)] = []
    let copiedQueue = DispatchQueue(label: "copied", attributes: .concurrent)

    var mock = FileIO.mock
    mock.findFiles = { _ in
      [
        "en/articles/hello.md",
        "en/articles/chart.png",
        "nl/articles/hello.md",
        "nl/articles/chart.png",
        "static/style.css",
      ]
    }
    mock.write = { _, _ in }
    mock.copy = { from, to in
      copiedQueue.sync(flags: .barrier) {
        copiedFiles.append((from: from, to: to))
      }
    }

    _ = try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en", localizedOutputFolders: ["articles": ["nl": "artikelen"]])
      .register(
        folder: "articles",
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: ["date": "2025-01-01"])],
        writers: []
      )
      .run()

    let finalCopied = copiedQueue.sync { copiedFiles }

    // English static file: default locale, no prefix, folder stays "articles"
    XCTAssertTrue(finalCopied.contains(where: { $0.to == "root/output/articles/chart.png" }))

    // Dutch static file: locale prefix + localized folder name
    XCTAssertTrue(finalCopied.contains(where: { $0.to == "root/output/nl/artikelen/chart.png" }))

    // Files outside locale folders are unaffected
    XCTAssertTrue(finalCopied.contains(where: { $0.to == "root/output/static/style.css" }))
  }

  func testI18nWithNested() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in
      [
        "en/docs/guide-a/intro.md",
        "en/docs/guide-a/advanced.md",
        "en/docs/guide-b/intro.md",
        "nl/docs/guide-a/intro.md",
        "nl/docs/guide-a/advanced.md",
        "nl/docs/guide-b/intro.md",
      ]
    }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    let saga = try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en")
      .register(
        folder: "docs",
        metadata: EmptyMetadata.self,
        writers: [
          .listWriter({ context in "parent:\(context.locale ?? "nil"):\(context.items.count)" }, output: "index.html"),
        ],
        nested: { child in
          child.register(
            metadata: EmptyMetadata.self,
            readers: [.mock(frontmatter: ["date": "2025-01-01"])],
            writers: [
              .itemWriter { context in "child:\(context.locale ?? "nil")" },
            ]
          )
        }
      )
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }

    // Child items should be written per locale
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/docs/guide-a/intro/index.html" && $0.content == "child:en" }))
    XCTAssertTrue(finalWrittenPages.contains(where: { $0.destination == "root/output/nl/docs/guide-a/intro/index.html" && $0.content == "child:nl" }))

    // Parent list should show per-locale item counts
    let enParent = finalWrittenPages.first { $0.destination == "root/output/docs/index.html" }
    let nlParent = finalWrittenPages.first { $0.destination == "root/output/nl/docs/index.html" }
    XCTAssertNotNil(enParent)
    XCTAssertNotNil(nlParent)

    // Each locale's parent should have 2 child guides (guide-a, guide-b)
    XCTAssertEqual(enParent?.content, "parent:en:2")
    XCTAssertEqual(nlParent?.content, "parent:nl:2")

    // All items should have locale set
    XCTAssertTrue(saga.allItems.allSatisfy { $0.locale != nil })

    // Items should have translations linked
    let enIntro = saga.allItems.first { $0.locale == "en" && $0.relativeSource.string.contains("guide-a/intro") }
    let nlIntro = saga.allItems.first { $0.locale == "nl" && $0.relativeSource.string.contains("guide-a/intro") }
    XCTAssertTrue(enIntro?.translations["nl"] === nlIntro)
  }

  func testCreatePageForEachLocale() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.findFiles = { _ in
      [
        "en/articles/hello.md",
        "en/articles/world.md",
        "nl/articles/hello.md",
      ]
    }
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    _ = try await Saga(input: "input", output: "output", fileIO: mock)
      .i18n(locales: ["en", "nl"], defaultLocale: "en")
      .register(
        folder: "articles",
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: ["date": "2025-01-01"])],
        writers: []
      )
      .createPage("index.html", forEachLocale: { context in
        let locale = context.locale ?? "nil"
        let count = context.allItems.count
        let translations = context.translations.sorted(by: { $0.key < $1.key }).map { "\($0.key):\($0.value)" }.joined(separator: ",")
        return "\(locale):\(count):\(translations)"
      })
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }
    XCTAssertEqual(finalWrittenPages.count, 2)

    // English homepage at root with only English items
    let enHome = finalWrittenPages.first { $0.destination == "root/output/index.html" }
    XCTAssertNotNil(enHome)
    XCTAssertTrue(try XCTUnwrap(enHome?.content.hasPrefix("en:2:")))

    // Dutch homepage at nl/ with only Dutch items
    let nlHome = finalWrittenPages.first { $0.destination == "root/output/nl/index.html" }
    XCTAssertNotNil(nlHome)
    XCTAssertTrue(try XCTUnwrap(nlHome?.content.hasPrefix("nl:1:")))

    // Both should have translations pointing to each other
    XCTAssertTrue(try XCTUnwrap(enHome?.content.contains("en:/")))
    XCTAssertTrue(try XCTUnwrap(enHome?.content.contains("nl:/nl/")))
    XCTAssertTrue(try XCTUnwrap(nlHome?.content.contains("en:/")))
    XCTAssertTrue(try XCTUnwrap(nlHome?.content.contains("nl:/nl/")))
  }

  func testCreatePageForEachLocaleWithoutI18n() async throws {
    let writtenPagesQueue = DispatchQueue(label: "writtenPages", attributes: .concurrent)
    nonisolated(unsafe) var writtenPages: [WrittenPage] = []

    var mock = FileIO.mock
    mock.write = { destination, content in
      writtenPagesQueue.sync(flags: .barrier) {
        writtenPages.append(.init(destination: destination, content: content))
      }
    }

    _ = try await Saga(input: "input", output: "output", fileIO: mock)
      .register(
        metadata: EmptyMetadata.self,
        readers: [.mock(frontmatter: ["date": "2025-01-01"])],
        writers: []
      )
      .createPage("index.html", forEachLocale: { context in
        "locale:\(context.locale ?? "nil")"
      })
      .run()

    let finalWrittenPages = writtenPagesQueue.sync { writtenPages }
    XCTAssertEqual(finalWrittenPages.count, 1)

    // Without i18n, behaves like regular createPage
    XCTAssertTrue(finalWrittenPages.contains(WrittenPage(destination: "root/output/index.html", content: "locale:nil")))
  }
}
