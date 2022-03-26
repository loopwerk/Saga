import Foundation
import PathKit

/// The main Saga class, used to configure and build your website.
///
/// ```swift
/// @main
/// struct Run {
///   static func main() async throws {
///     try await Saga(input: "content", output: "deploy", siteMetadata: EmptyMetadata())
///       // All files in the input folder will be parsed to html, and written to the output folder.
///       .register(
///         metadata: EmptyMetadata.self,
///         readers: [.parsleyMarkdownReader()],
///         writers: [
///           .itemWriter(swim(renderPage))
///         ]
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
public class Saga<SiteMetadata: Metadata> {
  /// The root working path. This is automatically set to the same folder that holds `Package.swift`.
  public let rootPath: Path

  /// The path that contains your text files, relative to the `rootPath`. For example "content".
  public let inputPath: Path

  /// The path that Saga will write the rendered website to, relative to the `rootPath`. For example "deploy".
  public let outputPath: Path

  /// The metadata used to hold site-wide information, such as the website name or URL. This will be included in all rendering contexts.
  public let siteMetadata: SiteMetadata

  /// An array of all file containters.
  public let fileStorage: [FileContainer]

  internal var processSteps = [AnyProcessStep]()
  internal let fileIO: FileIO

  public init(input: Path, output: Path = "deploy", siteMetadata: SiteMetadata, fileIO: FileIO = .diskAccess, originFilePath: StaticString = #file) throws {
    let originFile = Path("\(originFilePath)")
    rootPath = try fileIO.resolveSwiftPackageFolder(originFile)
    inputPath = rootPath + input
    outputPath = rootPath + output
    self.siteMetadata = siteMetadata
    self.fileIO = fileIO

    // 1. Find all files in the source folder
    let files = try fileIO.findFiles(inputPath)

    // 2. Turn the files into FileContainers so we can keep track if they're handled or not
    self.fileStorage = files.map { path in
      FileContainer(
        path: path
      )
    }
  }

  /// Register a new processing step.
  ///
  /// - Parameters:
  ///   - folder: The folder (relative to `input`) to operate on. If `nil`, it operates on the `input` folder itself.
  ///   - metadata: The metadata type used for the processing step. Required, but you can use ``EmptyMetadata`` if you don't need any custom metadata.
  ///   - readers: The readers that will be used by this step.
  ///   - itemWriteMode: The ``ItemWriteMode`` used by this step.
  ///   - filter: A filter to only include certain items from the input folder.
  ///   - writers: The writers that will be used by this step.
  /// - Returns: The Saga instance itself, so you can chain further calls onto it.
  @discardableResult
  public func register<M: Metadata>(folder: Path? = nil, metadata: M.Type, readers: [Reader<M>], itemWriteMode: ItemWriteMode = .moveToSubfolder, filter: @escaping ((Item<M>) -> Bool) = { _ in true }, writers: [Writer<M, SiteMetadata>]) throws -> Self {
    let step = ProcessStep(folder: folder, readers: readers, filter: filter, writers: writers)
    self.processSteps.append(
      .init(
        step: step,
        fileStorage: fileStorage,
        inputPath: inputPath,
        outputPath: outputPath,
        itemWriteMode: itemWriteMode,
        siteMetadata: siteMetadata,
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
    print("\(Date()) | Finished writers \(Double(writeTime) / 1_000_000_000)s")

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
