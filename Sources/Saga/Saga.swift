#if canImport(CryptoKit)
  import CryptoKit
#else
  import Crypto
#endif
import Foundation
import SagaPathKit

private nonisolated(unsafe) var _hashFunction: ((String) -> String)?
private let _hashLock = NSLock()

private func setHashFunction(_ fn: ((String) -> String)?) {
  _hashLock.withLock {
    _hashFunction = fn
  }
}

/// Returns a cache-busted file path by inserting a content hash into the filename.
///
/// Call this from any renderer to produce fingerprinted asset URLs:
/// ```swift
/// link(rel: "stylesheet", href: hashed("/static/output.css"))
/// // → "/static/output-a1b2c3d4.css"
/// ```
public func hashed(_ path: String) -> String {
  _hashLock.withLock {
    _hashFunction?(path) ?? path
  }
}

/// Whether the site is being served by `saga dev`.
///
/// This is `true` when the `SAGA_DEV` environment variable is set (which `saga dev` does
/// automatically). Use it to skip expensive work during development:
/// ```swift
/// .postProcess { html, _ in
///   isDev ? html : minifyHTML(html)
/// }
/// ```
public let isDev = ProcessInfo.processInfo.environment["SAGA_DEV"] != nil

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
public class Saga: @unchecked Sendable {
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
  let files: [(path: Path, relativePath: Path)]
  var handledPaths: Set<Path> = []
  var contentHashes: [String: String] = [:]

  // Generated page tracking, for the sitemap
  var generatedPages: [Path] = []
  private let generatedPagesLock = NSLock()
  
  // Pipeline steps
  typealias ReadStep = @Sendable () async throws -> [AnyItem]
  typealias WriteStep = @Sendable (_ stepItems: [AnyItem]) async throws -> Void
  var processSteps: [(read: ReadStep, write: WriteStep)] = []
  var postProcessors: [@Sendable (String, Path) throws -> String] = []

  // Write content to a file, applying any registered post-processors.
  // Also tracks the relative path in ``generatedPages``.
  func processedWrite(_ destination: Path, _ content: String) throws {
    let relativePath = try destination.relativePath(from: outputPath)
    generatedPagesLock.withLock { generatedPages.append(relativePath) }

    var result = content
    if !postProcessors.isEmpty {
      for transform in postProcessors {
        result = try transform(result, relativePath)
      }
    }
    try fileIO.write(destination, result)
  }

  public init(input: Path, output: Path = "deploy", fileIO: FileIO = .diskAccess, originFilePath: StaticString = #filePath) throws {
    let originFile = Path("\(originFilePath)")
    rootPath = try fileIO.resolveSwiftPackageFolder(originFile)
    inputPath = rootPath + input
    outputPath = rootPath + output
    self.fileIO = fileIO

    // Find all files in the source folder (filter out .DS_Store)
    let ip = inputPath
    let allFound = try fileIO.findFiles(inputPath).filter { $0.lastComponentWithoutExtension != ".DS_Store" }
    files = allFound.map { path in
      let relativePath = (try? path.relativePath(from: ip)) ?? Path("")
      return (path: path, relativePath: relativePath)
    }
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

  // MARK: - Register (file-based)

  /// Register a new processing step.
  ///
  /// - Parameters:
  ///   - folder: The folder (relative to `input`) to operate on. If `nil`, it operates on the `input` folder itself.
  ///   - metadata: The metadata type used for the processing step. You can use ``EmptyMetadata`` if you don't need any custom metadata (which is the default value).
  ///   - readers: The readers that will be used by this step.
  ///   - itemProcessor: A function to modify the generated ``Item`` as you see fit.
  ///   - filter: A filter to only include certain items from the input folder.
  ///   - claimExcludedItems: When an item is excluded by the `filter`, should this step claim it? If true (the default), excluded items won't be available to subsequent processing steps.
  ///   - itemWriteMode: The ``ItemWriteMode`` used by this step.
  ///   - sorting: A comparison function used to sort items. Defaults to date descending (newest first).
  ///   - writers: The writers that will be used by this step.
  /// - Returns: The Saga instance itself, so you can chain further calls onto it.
  @discardableResult
  @preconcurrency
  public func register<M: Metadata>(
    folder: Path? = nil,
    metadata: M.Type = EmptyMetadata.self,
    readers: [Reader],
    itemProcessor: (@Sendable (Item<M>) async -> Void)? = nil,
    filter: @escaping @Sendable (Item<M>) -> Bool = { _ in true },
    claimExcludedItems: Bool = true,
    itemWriteMode: ItemWriteMode = .moveToSubfolder,
    sorting: @escaping @Sendable (Item<M>, Item<M>) -> Bool = { $0.date > $1.date },
    writers: [Writer<M>]
  ) throws -> Self {
    // When folder ends with "/**", treat as nested with a deprecation warning.
    // This is purely about scoping (no parent/child), so use the fake-parents overload.
    if let folder, folder.string.hasSuffix("/**") {
      print("❕The '/**' folder suffix is deprecated. Use 'nested:' instead.")
      return try register(
        folder: folder.parent(), // removes `/**`
        nested: {
          .register(
            metadata: M.self,
            readers: readers,
            itemProcessor: itemProcessor,
            filter: filter,
            itemWriteMode: itemWriteMode,
            sorting: sorting,
            writers: writers
          )
        }
      )
    }

    addFileStep(
      folder: folder,
      readers: readers,
      itemProcessor: itemProcessor,
      filter: filter,
      claimExcludedItems: claimExcludedItems,
      itemWriteMode: itemWriteMode,
      sorting: sorting,
      writers: writers
    )

    return self
  }

  // MARK: - Register (nested)

  /// Register a processing step with nested per-subfolder processing.
  ///
  /// Each immediate subfolder under `folder` is processed independently. Nested items are read
  /// from the nested registration's readers, with writers scoped per subfolder.
  ///
  /// When `readers` is provided, parent items are read from those readers and parent/child
  /// relationships are wired automatically. When `readers` is empty (the default), Saga creates
  /// a synthetic `Item<EmptyMetadata>` per subfolder with `title` set to the subfolder name
  /// and `children` wired to the nested items.
  ///
  /// - Parameters:
  ///   - folder: The folder (relative to `input`) to operate on.
  ///   - metadata: The metadata type for parent items.
  ///   - readers: The readers for parent items. Defaults to `[]` (synthetic parents).
  ///   - itemProcessor: A function to modify parent items.
  ///   - filter: A filter for parent items.
  ///   - claimExcludedItems: Whether excluded parent items should be claimed.
  ///   - itemWriteMode: The ``ItemWriteMode`` for parent items.
  ///   - sorting: Sort order for parent items.
  ///   - writers: Writers for parent items (receive items with `children` populated).
  ///   - nested: A closure returning a ``NestedRegistration`` for per-subfolder child items.
  @discardableResult
  @preconcurrency
  public func register<M: Metadata, C: Metadata>(
    folder: Path,
    metadata: M.Type = EmptyMetadata.self,
    readers: [Reader] = [],
    itemProcessor: (@Sendable (Item<M>) async -> Void)? = nil,
    filter: @escaping @Sendable (Item<M>) -> Bool = { _ in true },
    claimExcludedItems: Bool = true,
    itemWriteMode: ItemWriteMode = .moveToSubfolder,
    sorting: @escaping @Sendable (Item<M>, Item<M>) -> Bool = { $0.date > $1.date },
    writers: [Writer<M>] = [],
    nested: () -> NestedRegistration<C>
  ) throws -> Self {
    addNestedStep(
      folder: folder,
      parentReaders: readers.isEmpty ? nil : readers,
      parentItemProcessor: itemProcessor,
      parentFilter: filter,
      claimExcludedItems: claimExcludedItems,
      parentItemWriteMode: itemWriteMode,
      parentSorting: sorting,
      parentWriters: writers,
      nested: nested()
    )

    return self
  }

  // MARK: - Register (fetch-based)

  /// Register a processing step that fetches items programmatically instead of reading from files.
  ///
  /// - Parameters:
  ///   - metadata: The metadata type used for the processing step. You can use ``EmptyMetadata`` if you don't need any custom metadata (which is the default value).
  ///   - fetch: An async function that returns an array of items.
  ///   - itemProcessor: A function to modify each fetched ``Item`` as you see fit.
  ///   - sorting: A comparison function used to sort items. Defaults to date descending (newest first).
  ///   - writers: The writers that will be used by this step.
  /// - Returns: The Saga instance itself, so you can chain further calls onto it.
  @discardableResult
  @preconcurrency
  public func register<M: Metadata>(
    metadata: M.Type = EmptyMetadata.self,
    fetch: @escaping @Sendable () async throws -> [Item<M>],
    itemProcessor: (@Sendable (Item<M>) async -> Void)? = nil,
    sorting: @escaping @Sendable (Item<M>, Item<M>) -> Bool = { $0.date > $1.date },
    writers: [Writer<M>]
  ) -> Self {
    register(
      read: { _ in
        let items = try await fetch().sorted(by: sorting)
        if let itemProcessor {
          for item in items {
            await itemProcessor(item)
          }
        }
        return items
      },
      write: { saga, stepItems in
        let items = stepItems.compactMap { $0 as? Item<M> }
        let context = WriterContext(
          items: items,
          allItems: saga.allItems,
          outputRoot: saga.outputPath,
          outputPrefix: Path(""),
          write: { try saga.processedWrite($0, $1) },
          resourcesByFolder: [:],
          subfolder: nil
        )
        try await withThrowingTaskGroup(of: Void.self) { group in
          for writer in writers {
            group.addTask { try await writer.run(context) }
          }
          try await group.waitForAll()
        }
      }
    )
  }

  // MARK: - Register (custom)

  /// Register a custom write-only step.
  ///
  /// Register a custom write-only steps for logic outside the standard pipeline:
  /// generate images, build a search index, or run any custom logic as part of your build.
  /// The closure runs during the write phase, after all readers have finished and items are sorted.
  ///
  /// ```swift
  /// try await Saga(input: "content", output: "deploy")
  ///   .register(...)
  ///   .register { saga in
  ///     // custom write logic with access to saga.allItems
  ///   }
  ///   .run()
  /// ```
  @discardableResult
  @preconcurrency
  public func register(write: @Sendable @escaping (Saga) async throws -> Void) -> Self {
    register(
      read: { _ in [] },
      write: { saga, _ in try await write(saga) }
    )
  }

  // MARK: - Post-processing & pages

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

  /// Create a template-driven page without needing an ``Item`` or markdown file.
  ///
  /// Use this for pages that are purely driven by a template, such as a homepage showing the latest articles,
  /// a search page, or a 404 page. The renderer receives a ``PageRenderingContext`` with access to all items
  /// across all processing steps.
  ///
  /// Pages created with `createPage` run after all registered writers have finished. This means
  /// ``PageRenderingContext/generatedPages`` contains every page written by writers, plus pages
  /// from earlier `createPage` calls. **Order matters**: place the sitemap last if it needs to
  /// see all other pages.
  ///
  /// ```swift
  /// try await Saga(input: "content", output: "deploy")
  ///   .register(...)
  ///   .createPage("index.html", using: swim(renderHome))
  ///   .createPage("sitemap.xml", using: sitemap(baseURL: siteURL))
  ///   .run()
  /// ```
  @discardableResult
  @preconcurrency
  public func createPage(_ output: Path, using renderer: @Sendable @escaping (PageRenderingContext) async throws -> String) -> Self {
    register { saga in
      let context = PageRenderingContext(allItems: saga.allItems, outputPath: output, generatedPages: saga.generatedPages)
      let stringToWrite = try await renderer(context)
      try saga.processedWrite(saga.outputPath + output, stringToWrite)
    }
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
    var stepResults: [[AnyItem]] = []
    for step in processSteps {
      let items = try await step.read()
      stepResults.append(items)
      allItems.append(contentsOf: items)
    }

    let readEnd = DispatchTime.now()
    let readTime = readEnd.uptimeNanoseconds - readStart.uptimeNanoseconds
    print("\(logTimestamp()) | Finished read phase in \(Double(readTime) / 1_000_000_000)s")

    // Sort all items by date descending
    allItems.sort { $0.date > $1.date }

    // Clean the output folder
    try fileIO.deletePath(outputPath)

    // Copy all unhandled files as-is to the output folder first,
    // so that the directory structure exists for the write phase.
    let copyStart = DispatchTime.now()

    try await withThrowingTaskGroup(of: Void.self) { group in
      for file in unhandledFiles {
        group.addTask {
          let output = self.outputPath + file.relativePath
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

    if !isDev {
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
    for (step, items) in zip(processSteps, stepResults) {
      try await step.write(items)
    }

    let writeEnd = DispatchTime.now()
    let writeTime = writeEnd.uptimeNanoseconds - writeStart.uptimeNanoseconds
    print("\(logTimestamp()) | Finished write phase in \(Double(writeTime) / 1_000_000_000)s")

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

    let totalEnd = DispatchTime.now()
    let totalTime = totalEnd.uptimeNanoseconds - totalStart.uptimeNanoseconds
    print("\(logTimestamp()) | All done in \(Double(totalTime) / 1_000_000_000)s")

    return self
  }
}
