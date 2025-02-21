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
///       // Run the step we registered above
///       .run()
///
///       // All the remaining files that were not parsed to markdown, so for example images, raw html files and css,
///       // are copied as-is to the output folder.
///       .staticFiles()
///   }
/// }
/// ```
public class Saga {
  /// The root working path. This is automatically set to the same folder that holds `Package.swift`.
  public let rootPath: Path

  /// The path that contains your text files, relative to the `rootPath`. For example "content".
  public let inputPath: Path

  /// The path that Saga will write the rendered website to, relative to the `rootPath`. For example "deploy".
  public let outputPath: Path

  /// An array of all file containters.
  public let fileStorage: [FileContainer]

  internal var processSteps = [AnyProcessStep]()
  internal let fileIO: FileIO

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
    self.fileStorage = files.map { path in
      let relativePath = (try? path.relativePath(from: ip)) ?? Path("")
      return FileContainer(path: path, relativePath: relativePath)
    }
  }

  /// Register a new processing step.
  ///
  /// - Parameters:
  ///   - folder: The folder (relative to `input`) to operate on. If `nil`, it operates on the `input` folder itself.
  ///   - metadata: The metadata type used for the processing step. You can use ``EmptyMetadata`` if you don't need any custom metadata (which is the default value).
  ///   - readers: The readers that will be used by this step.
  ///   - itemProcessor: A function to modify the generated ``Item`` as you see fit.
  ///   - filter: A filter to only include certain items from the input folder.
  ///   - itemWriteMode: The ``ItemWriteMode`` used by this step.
  ///   - writers: The writers that will be used by this step.
  /// - Returns: The Saga instance itself, so you can chain further calls onto it.
  @discardableResult
  public func register<M: Metadata>(folder: Path? = nil, metadata: M.Type = EmptyMetadata.self, readers: [Reader], itemProcessor: ((Item<M>) async -> Void)? = nil, filter: @escaping ((Item<M>) -> Bool) = { _ in true }, itemWriteMode: ItemWriteMode = .moveToSubfolder, writers: [Writer<M>]) throws -> Self {
    let step = ProcessStep(folder: folder, readers: readers, itemProcessor: itemProcessor, filter: filter, writers: writers)
    self.processSteps.append(
      .init(
        step: step,
        fileStorage: fileStorage,
        inputPath: inputPath,
        outputPath: outputPath,
        itemWriteMode: itemWriteMode,
        fileIO: fileIO
      ))
    return self
  }

  /// Execute all the registered steps.
  @discardableResult
  public func run() async throws -> Self {
    print("\(Date()) | Starting run")

    // Run all the readers for all the steps, which turns raw content into
    // Items, and stores them within the step.
    let readStart = DispatchTime.now()
    for step in processSteps {
      try await step.runReaders()
    }

    let readEnd = DispatchTime.now()
    let readTime = readEnd.uptimeNanoseconds - readStart.uptimeNanoseconds
    print("\(Date()) | Finished readers in \(Double(readTime) / 1_000_000_000)s")

    // Clean the output folder
    try fileIO.deletePath(outputPath)

    // And run all the writers for all the steps, using those stored Items.
    let writeStart = DispatchTime.now()
    for step in processSteps {
      try step.runWriters()
    }

    let writeEnd = DispatchTime.now()
    let writeTime = writeEnd.uptimeNanoseconds - writeStart.uptimeNanoseconds
    print("\(Date()) | Finished writers in \(Double(writeTime) / 1_000_000_000)s")

    return self
  }

  /// Copy all unhandled files as-is to the output folder.
  @discardableResult
  public func staticFiles() throws -> Self {
    let start = DispatchTime.now()

    let unhandledPaths = fileStorage
      .filter { $0.handled == false }
      .map(\.path)

    for path in unhandledPaths {
      let relativePath = try path.relativePath(from: inputPath)
      let input = path
      let output = outputPath + relativePath
      try fileIO.mkpath(output.parent())
      try fileIO.copy(input, output)
    }

    let end = DispatchTime.now()
    let time = end.uptimeNanoseconds - start.uptimeNanoseconds
    print("\(Date()) | Finished copying static files in \(Double(time) / 1_000_000_000)s")

    return self
  }
}
