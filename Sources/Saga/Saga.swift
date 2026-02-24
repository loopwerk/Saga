import Foundation
import PathKit

/// The main Saga class, used to configure and build your website.
///
/// ```swift
/// @main
/// struct Run {
///   static func main() async throws {
///     try await Saga(input: "content", output: "deploy")
///       // All files in the input folder will be parsed to html, and written to the output folder.
///       .register(
///         metadata: EmptyMetadata.self,
///         readers: [.parsleyMarkdownReader],
///         writers: [.itemWriter(swim(renderPage))]
///       )
///
///       // Run the steps we registered above.
///       // Static files (images, css, etc.) are copied automatically.
///       .run()
///   }
/// }
/// ```
public class Saga: @unchecked Sendable {
  /// The root working path. This is automatically set to the same folder that holds `Package.swift`.
  public let rootPath: Path

  /// The path that contains your text files, relative to the `rootPath`. For example "content".
  public let inputPath: Path

  /// The path that Saga will write the rendered website to, relative to the `rootPath`. For example "deploy".
  public let outputPath: Path

  /// An array of all file containters.
  public let fileStorage: [FileContainer]

  /// All items across all registered processing steps.
  public internal(set) var allItems: [AnyItem] = []

  var processSteps = [AnyProcessStep]()
  let fileIO: FileIO

  public init(input: Path, output: Path = "deploy", fileIO: FileIO = .diskAccess, originFilePath: StaticString = #file) throws {
    let originFile = Path("\(originFilePath)")
    rootPath = try fileIO.resolveSwiftPackageFolder(originFile)
    inputPath = rootPath + input
    outputPath = rootPath + output
    self.fileIO = fileIO

    // 1. Find all files in the source folder (filter out .DS_Store)
    let files = try fileIO.findFiles(inputPath).filter { $0.lastComponentWithoutExtension != ".DS_Store" }

    // 2. Turn the files into FileContainers so we can keep track if they're handled or not
    let ip = inputPath
    fileStorage = files.map { path in
      let relativePath = (try? path.relativePath(from: ip)) ?? Path("")
      return FileContainer(path: path, relativePath: relativePath)
    }
  }

  /// Register a new processing step.
  ///
  /// - Parameters:
  ///   - folder: The folder (relative to `input`) to operate on. If `nil`, it operates on the `input` folder itself.
  ///     Append `/**` (e.g. `"photos/**"`) to create a separate processing step for each subfolder.
  ///     Each subfolder gets its own scoped `items` array, `previous`/`next` navigation, and writers.
  ///   - metadata: The metadata type used for the processing step. You can use ``EmptyMetadata`` if you don't need any custom metadata (which is the default value).
  ///   - readers: The readers that will be used by this step.
  ///   - itemProcessor: A function to modify the generated ``Item`` as you see fit.
  ///   - filter: A filter to only include certain items from the input folder.
  ///   - filteredOutItemsAreHandled: When an item is ignored by the `filter`, is it then marked as handled? If true, it won't be handled by subsequent processing steps.
  ///   - itemWriteMode: The ``ItemWriteMode`` used by this step.
  ///   - sorting: A comparison function used to sort items. Defaults to date descending (newest first).
  ///   - writers: The writers that will be used by this step.
  /// - Returns: The Saga instance itself, so you can chain further calls onto it.
  @discardableResult
  public func register<M: Metadata>(folder: Path? = nil, metadata: M.Type = EmptyMetadata.self, readers: [Reader], itemProcessor: ((Item<M>) async -> Void)? = nil, filter: @escaping ((Item<M>) -> Bool) = { _ in true }, filteredOutItemsAreHandled: Bool = true, itemWriteMode: ItemWriteMode = .moveToSubfolder, sorting: @escaping (Item<M>, Item<M>) -> Bool = { $0.date > $1.date }, writers: [Writer<M>]) throws -> Self {
    // When folder ends with "/**", create one ProcessStep per subfolder
    if let folder = folder, folder.string.hasSuffix("/**") {
      let baseFolder = Path(String(folder.string.dropLast(3)))
      let baseFolderPrefix = baseFolder.string + "/"
      let supportedExtensions = Set(readers.flatMap(\.supportedExtensions))

      let subFolders = Set(
        fileStorage
          .filter { container in
            guard container.relativePath.string.hasPrefix(baseFolderPrefix) else { return false }
            return supportedExtensions.contains(container.path.extension ?? "")
          }
          .map { $0.relativePath.parent() }
      )

      for subFolder in subFolders.sorted(by: { $0.string < $1.string }) {
        let step = ProcessStep(folder: subFolder, readers: readers, itemProcessor: itemProcessor, filter: filter, filteredOutItemsAreHandled: filteredOutItemsAreHandled, sorting: sorting, writers: writers)
        processSteps.append(
          .init(
            step: step,
            saga: self,
            itemWriteMode: itemWriteMode
          )
        )
      }
    } else {
      let step = ProcessStep(folder: folder, readers: readers, itemProcessor: itemProcessor, filter: filter, filteredOutItemsAreHandled: filteredOutItemsAreHandled, sorting: sorting, writers: writers)
      processSteps.append(
        .init(
          step: step,
          saga: self,
          itemWriteMode: itemWriteMode
        )
      )
    }
    return self
  }

  /// Register a processing step that fetches items programmatically instead of reading from files.
  ///
  /// - Parameters:
  ///   - metadata: The metadata type used for the processing step. You can use ``EmptyMetadata`` if you don't need any custom metadata (which is the default value).
  ///   - fetch: An async function that returns an array of items.
  ///   - sorting: A comparison function used to sort items. Defaults to date descending (newest first).
  ///   - writers: The writers that will be used by this step.
  /// - Returns: The Saga instance itself, so you can chain further calls onto it.
  @discardableResult
  public func register<M: Metadata>(metadata: M.Type = EmptyMetadata.self, fetch: @escaping () async throws -> [Item<M>], sorting: @escaping (Item<M>, Item<M>) -> Bool = { $0.date > $1.date }, writers: [Writer<M>]) -> Self {
    var items: [Item<M>] = []
    return register(
      read: { saga in
        items = try await fetch().sorted(by: sorting)
        saga.allItems.append(contentsOf: items)
      },
      write: { saga in
        try await withThrowingTaskGroup(of: Void.self) { group in
          for writer in writers {
            group.addTask {
              try await writer.run(items, saga.allItems, saga.fileStorage, saga.outputPath, "", saga.fileIO)
            }
          }
          try await group.waitForAll()
        }
      }
    )
  }

  /// Register a custom write-only processing step.
  ///
  /// Use this for custom logic that doesn't fit the standard reader/writer pipeline.
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
  public func register(write: @escaping (Saga) async throws -> Void) -> Self {
    processSteps.append(
      .init(read: { _ in }, write: write, saga: self)
    )
    return self
  }

  /// Register a custom processing step with user-provided read and write closures.
  ///
  /// Use this for custom logic that doesn't fit the standard reader/writer pipeline.
  /// The read closure runs during the read phase (before items are sorted),
  /// and the write closure runs during the write phase (after all readers have finished).
  @discardableResult
  public func register(read: @escaping (Saga) async throws -> Void, write: @escaping (Saga) async throws -> Void) -> Self {
    processSteps.append(
      .init(read: read, write: write, saga: self)
    )
    return self
  }
  
  /// Create a template-driven page without needing an ``Item`` or markdown file.
  ///
  /// Use this for pages that are purely driven by a template, such as a homepage showing the latest articles,
  /// a search page, or a 404 page. The renderer receives a ``PageRenderingContext`` with access to all items
  /// across all processing steps.
  ///
  /// ```swift
  /// try await Saga(input: "content", output: "deploy")
  ///   .register(
  ///     folder: "articles",
  ///     metadata: ArticleMetadata.self,
  ///     readers: [.parsleyMarkdownReader],
  ///     writers: [.listWriter(swim(renderArticles))]
  ///   )
  ///   .createPage("index.html", using: swim(renderHome))
  ///   .run()
  /// ```
  @discardableResult
  public func createPage(_ output: Path, using renderer: @escaping (PageRenderingContext) async throws -> String) -> Self {
    register(write: { saga in
      let context = PageRenderingContext(allItems: saga.allItems, outputPath: output)
      let stringToWrite = try await renderer(context)
      try saga.fileIO.write(saga.outputPath + output, stringToWrite)
    })
  }
  
  /// Execute all the registered steps.
  @discardableResult
  public func run() async throws -> Self {
    print("\(Date()) | Starting run")

    // Run all the readers for all the steps sequentially to ensure proper order,
    // which turns raw content into Items, and stores them within the step.
    let readStart = DispatchTime.now()
    for step in processSteps {
      try await step.runReaders()
    }

    let readEnd = DispatchTime.now()
    let readTime = readEnd.uptimeNanoseconds - readStart.uptimeNanoseconds
    print("\(Date()) | Finished readers in \(Double(readTime) / 1_000_000_000)s")

    // Sort all items by date descending
    allItems.sort { $0.date > $1.date }

    // Clean the output folder
    try fileIO.deletePath(outputPath)

    // And run all the writers for all the steps, using those stored Items.
    let writeStart = DispatchTime.now()
    try await withThrowingTaskGroup(of: Void.self) { group in
      for step in processSteps {
        group.addTask {
          try await step.runWriters()
        }
      }
      try await group.waitForAll()
    }

    let writeEnd = DispatchTime.now()
    let writeTime = writeEnd.uptimeNanoseconds - writeStart.uptimeNanoseconds
    print("\(Date()) | Finished writers in \(Double(writeTime) / 1_000_000_000)s")

    // Copy all unhandled files as-is to the output folder
    let copyStart = DispatchTime.now()

    let unhandledPaths = fileStorage
      .filter { $0.handled == false }
      .map(\.path)

    try await withThrowingTaskGroup(of: Void.self) { group in
      for path in unhandledPaths {
        group.addTask {
          let relativePath = try path.relativePath(from: self.inputPath)
          let input = path
          let output = self.outputPath + relativePath
          try self.fileIO.mkpath(output.parent())
          try self.fileIO.copy(input, output)
        }
      }
      try await group.waitForAll()
    }

    let copyEnd = DispatchTime.now()
    let copyTime = copyEnd.uptimeNanoseconds - copyStart.uptimeNanoseconds
    print("\(Date()) | Finished copying static files in \(Double(copyTime) / 1_000_000_000)s")

    return self
  }

  /// Deprecated: static files are now copied automatically by ``run()``.
  @available(*, deprecated, message: "Static files are now copied automatically by run(). You can remove this call.")
  @discardableResult
  public func staticFiles() async throws -> Self {
    return self
  }
}
