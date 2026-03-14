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
  let files: [(path: Path, relativePath: Path)]
  var handledPaths: Set<Path> = []
  var contentHashes: [String: String] = [:]

  // Generated page tracking, for the sitemap
  var generatedPages: [Path] = []
  private let generatedPagesLock = NSLock()

  // Post processors
  var postProcessors: [@Sendable (String, Path) throws -> String] = []

  // Write content to a file, applying any registered post-processors.
  // Also tracks the relative path in ``generatedPages``.
  func processedWrite(_ destination: Path, _ content: String) throws {
    let relativePath = try destination.relativePath(from: outputPath)
    generatedPagesLock.withLock { generatedPages.append(relativePath) }

    let result = try postProcessors.reduce(content) { content, transform in try transform(content, relativePath) }
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
    var stepResults: [[AnyItem]] = []
    for step in steps {
      let items = try await step.read(self, nil)
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
    for (step, items) in zip(steps, stepResults) {
      try await step.write(self, items, step.outputPrefix, nil)
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
