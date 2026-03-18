#if canImport(CryptoKit)
  import CryptoKit
#else
  import Crypto
#endif
import Foundation
import SagaPathKit

/// The main Saga class, used to configure and build your website.
///
/// ```swift
/// try await Saga(input: "content", output: "deploy")
///   // All files in the input folder will be parsed to html, and written to the output folder.
///   .register(
///     metadata: EmptyMetadata.self,
///     readers: [.parsleyMarkdownReader],
///     writers: [.itemWriter(swim(renderPage))]
///   )
///
///   // Run the steps we registered above.
///   // Static files (images, css, etc.) are copied automatically.
///   .run()
/// ```
public class Saga: StepBuilder, @unchecked Sendable {
  /// The root working path. This is automatically set to the same folder that holds `Package.swift`.
  public let rootPath: Path

  /// The path that contains your text files, relative to the `rootPath`. For example "content".
  public let inputPath: Path

  /// The path that Saga will write the rendered website to, relative to the `rootPath`. For example "deploy".
  public let outputPath: Path

  /// All ``Item``s across all registered processing steps.
  public internal(set) var allItems: [AnyItem] = []

  let fileIO: FileIO

  // Internal file tracking
  var handledPaths: Set<Path> = []
  var contentHashes: [String: String] = [:]

  // Generated page tracking, for the sitemap
  private var writtenPages: [(path: Path, locale: String?)] = []
  private let writtenPagesLock = NSLock()

  /// All generated pages, grouped by translation.
  var generatedPages: [[String: Path]] {
    guard i18nConfig != nil else {
      return writtenPages.map { ["": $0.path] }
    }

    var groups: [String: [String: Path]] = [:]
    for page in writtenPages {
      let key: String
      if let locale = page.locale {
        let prefix = locale + "/"
        key = page.path.string.hasPrefix(prefix) ? String(page.path.string.dropFirst(prefix.count)) : page.path.string
      } else {
        key = page.path.string
      }
      groups[key, default: [:]][page.locale ?? ""] = page.path
    }

    return Array(groups.values)
  }

  /// Post processors
  var postProcessors: [@Sendable (String, Path) throws -> String] = []

  /// Write content to a file, applying any registered post-processors.
  /// Also tracks the relative path in ``writtenPages``.
  func processedWrite(_ destination: Path, _ content: String, locale: String? = nil) throws {
    let relativePath = try destination.relativePath(from: outputPath)
    writtenPagesLock.withLock { writtenPages.append((path: relativePath, locale: locale)) }

    let result = try postProcessors.reduce(content) { content, transform in try transform(content, relativePath) }
    try fileIO.write(destination, result)
  }

  public init(input: Path, output: Path = "deploy", fileIO: FileIO = .diskAccess, originFilePath: StaticString = #filePath) throws {
    let originFile = Path("\(originFilePath)")
    let rootPath = try fileIO.resolveSwiftPackageFolder(originFile)

    self.rootPath = rootPath
    inputPath = rootPath + input
    outputPath = rootPath + output
    self.fileIO = fileIO

    // Find all files in the source folder (filter out .DS_Store)
    let allFound = try fileIO.findFiles(inputPath).filter { $0.lastComponentWithoutExtension != ".DS_Store" }
    let computedFiles = allFound.map { path in
      let relativePath = (try? path.relativePath(from: rootPath + input)) ?? Path("")
      return (path: path, relativePath: relativePath)
    }

    super.init(files: computedFiles, workingPath: Path(""))
  }

  /// Files not claimed by any processing step.
  var unhandledFiles: [(path: Path, relativePath: Path)] {
    files.filter { !handledPaths.contains($0.path) }
  }

  /// Unhandled files grouped by their relative parent folder.
  func resourcesByFolder() -> [Path: [Path]] {
    var result: [Path: [Path]] = [:]
    for file in unhandledFiles {
      result[file.relativePath.parent(), default: []].append(file.path)
    }
    return result
  }

  // MARK: - Internationalization

  /// Configure internationalization for this site.
  ///
  /// When i18n is configured, each `register` call automatically processes content for all locales.
  /// Items are tagged with their locale, translations are linked by matching source filenames,
  /// and writers run per-locale to generate separate list/tag/year pages for each language.
  ///
  /// ```swift
  /// try await Saga(input: "content", output: "deploy")
  ///   .i18n(locales: ["en", "nl"], defaultLocale: "en", style: .directory)
  ///   .register(...)
  ///   .run()
  /// ```
  @discardableResult
  public func i18n(
    locales: [String],
    defaultLocale: String,
    style: I18NStyle = .directory,
    defaultLocaleInSubdir: Bool = false
  ) -> Self {
    i18nConfig = I18NConfig(
      locales: locales,
      defaultLocale: defaultLocale,
      style: style,
      defaultLocaleInSubdir: defaultLocaleInSubdir
    )
    return self
  }

  // MARK: - Post-processing

  /// Apply a transform to every file written by Saga.
  ///
  /// The transform receives the rendered content and relative output path.
  /// Multiple calls stack: each wraps the previous write.
  ///
  /// ```swift
  /// try await Saga(input: "content", output: "deploy")
  ///   .register(...)
  ///   .postProcess { html, path in
  ///     minifyHTML(html)
  ///   }
  ///   .run()
  /// ```
  @discardableResult
  @preconcurrency
  public func postProcess(_ transform: @Sendable @escaping (String, Path) throws -> String) -> Self {
    postProcessors.append(transform)
    return self
  }

  // MARK: - Run

  /// Execute all the registered steps.
  @discardableResult
  public func run() async throws -> Self {
    let logDateFormatter = DateFormatter()
    logDateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    func logTimestamp() -> String {
      logDateFormatter.string(from: Date())
    }

    let totalStart = DispatchTime.now()
    print("\(logTimestamp()) | Starting run")

    // Run all the readers for all the steps sequentially to ensure proper order,
    // which turns raw content into Items, and stores them within the step.
    let readStart = DispatchTime.now()
    for step in steps {
      let items = try await step.read(self)
      allItems.append(contentsOf: items)
    }

    // Sort all items by date descending
    allItems.sort { $0.date > $1.date }

    // Link translations
    if let i18n = i18nConfig {
      linkTranslations(items: allItems, config: i18n)
    }

    let readEnd = DispatchTime.now()
    let readTime = readEnd.uptimeNanoseconds - readStart.uptimeNanoseconds
    print("\(logTimestamp()) | Finished read phase in \(Double(readTime) / 1_000_000_000)s")

    // Clean the output folder
    try fileIO.deletePath(outputPath)

    // Copy all unhandled files as-is to the output folder first,
    // so that the directory structure exists for the write phase.
    let copyStart = DispatchTime.now()

    try await withThrowingTaskGroup(of: Void.self) { group in
      for file in unhandledFiles {
        group.addTask {
          var outputRelative = file.relativePath

          // For directory-style i18n, rewrite locale-prefixed static files
          if let i18n = self.i18nConfig, i18n.style == .directory {
            let first = file.relativePath.string.split(separator: "/").first.map(String.init) ?? ""
            if i18n.locales.contains(first), !i18n.shouldPrefix(locale: first) {
              // Strip locale prefix for default locale
              let stripped = String(file.relativePath.string.dropFirst(first.count + 1))
              outputRelative = Path(stripped)
            }
          }

          let output = self.outputPath + outputRelative
          try self.fileIO.mkpath(output.parent())
          try self.fileIO.copy(file.path, output)
        }
      }
      try await group.waitForAll()
    }

    let copyEnd = DispatchTime.now()
    let copyTime = copyEnd.uptimeNanoseconds - copyStart.uptimeNanoseconds
    print("\(logTimestamp()) | Finished copying static files in \(Double(copyTime) / 1_000_000_000)s")

    // Set up the hash function so renderers can call hashed() during the write phase.
    // In dev mode, skip hashing so filenames stay stable for auto-reload.
    // The closure runs under _hashLock (acquired by the global hashed() function),
    // so contentHashes access is thread-safe without additional locking.

    if !Saga.isDev {
      setHashFunction { path in
        let stripped = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let file = self.files.first(where: { $0.relativePath.string == stripped }) else {
          return path
        }

        if let cached = self.contentHashes[stripped] {
          let p = Path(stripped)
          let ext = p.extension ?? ""
          let name = p.parent() + Path(p.lastComponentWithoutExtension + "-" + cached + (ext.isEmpty ? "" : ".\(ext)"))
          return (path.hasPrefix("/") ? "/" : "") + name.string
        }

        do {
          let data = try self.fileIO.read(file.path)
          let digest = Insecure.MD5.hash(data: data)
          let hashString = String(digest.map { String(format: "%02x", $0) }.joined().prefix(8))
          self.contentHashes[stripped] = hashString

          let p = Path(stripped)
          let ext = p.extension ?? ""
          let name = p.parent() + Path(p.lastComponentWithoutExtension + "-" + hashString + (ext.isEmpty ? "" : ".\(ext)"))
          return (path.hasPrefix("/") ? "/" : "") + name.string
        } catch {
          return path
        }
      }
    }

    // Run all writers sequentially
    // processedWrite tracks generated paths automatically.
    let writeStart = DispatchTime.now()
    for step in steps {
      try await step.write(self)
    }

    // Generate i18n redirects
    if let i18n = i18nConfig {
      if i18n.defaultLocaleInSubdir {
        // Redirect / → /{defaultLocale}/
        let from = Path("index.html")
        if !writtenPages.contains(where: { $0.path == from }) {
          let dest = outputPath + from
          try fileIO.mkpath(dest.parent())
          try processedWrite(dest, Self.redirectHTML(to: "/\(i18n.defaultLocale)/"))
        }
      } else {
        // Redirect /{defaultLocale}/... → /... for every default-locale page
        let defaultLocalePages = writtenPages.filter { $0.locale == i18n.defaultLocale }
        for page in defaultLocalePages {
          let prefixedPath = Path(i18n.defaultLocale) + page.path
          let dest = outputPath + prefixedPath
          try fileIO.mkpath(dest.parent())
          try processedWrite(dest, Self.redirectHTML(to: page.path.url))
        }
      }
    }

    // Copy hashed versions of files that were referenced via hashed()
    for file in unhandledFiles where contentHashes[file.relativePath.string] != nil {
      let relativePath = file.relativePath
      let ext = relativePath.extension ?? ""
      let hashedName = relativePath.lastComponentWithoutExtension + "-" + contentHashes[relativePath.string]! + (ext.isEmpty ? "" : ".\(ext)")
      let hashedRelativePath = relativePath.parent() + Path(hashedName)
      let destination = outputPath + hashedRelativePath
      try fileIO.mkpath(destination.parent())
      try fileIO.copy(file.path, destination)
    }

    // Reset the hash function
    setHashFunction(nil)

    let writeEnd = DispatchTime.now()
    let writeTime = writeEnd.uptimeNanoseconds - writeStart.uptimeNanoseconds
    print("\(logTimestamp()) | Finished write phase in \(Double(writeTime) / 1_000_000_000)s")

    let totalEnd = DispatchTime.now()
    let totalTime = totalEnd.uptimeNanoseconds - totalStart.uptimeNanoseconds
    print("\(logTimestamp()) | All done in \(Double(totalTime) / 1_000_000_000)s")

    return self
  }
}
