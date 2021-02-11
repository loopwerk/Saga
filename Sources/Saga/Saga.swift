import Foundation
import PathKit

public class Saga<SiteMetadata: Metadata> {
  public let rootPath: Path
  public let inputPath: Path
  public let outputPath: Path
  public let siteMetadata: SiteMetadata

  public let fileStorage: [FileContainer]
  internal var processSteps = [AnyProcessStep]()

  public init(input: Path, output: Path, siteMetadata: SiteMetadata, originFilePath: StaticString = #file) throws {
    let originFile = Path("\(originFilePath)")
    rootPath = try originFile.resolveSwiftPackageFolder()
    inputPath = rootPath + input
    outputPath = rootPath + output
    self.siteMetadata = siteMetadata

    // 1. Find all files in the source folder
    let files = try inputPath.recursiveChildren().filter(\.isFile)

    // 2. Turn the files into FileContainers so we can keep track if they're handled or not
    self.fileStorage = files.map { path in
      FileContainer(
        path: path
      )
    }

    // 3. Clean the output folder
    if outputPath.exists {
      try outputPath.delete()
    }
  }

  @discardableResult
  public func register<M: Metadata>(folder: Path? = nil, metadata: M.Type, readers: [Reader<M>], pageWriteMode: PageWriteMode = .moveToSubfolder, filter: @escaping ((Page<M>) -> Bool) = { _ in true }, writers: [Writer<M, SiteMetadata>]) throws -> Self {
    let step = ProcessStep(folder: folder, readers: readers, filter: filter, writers: writers)
    self.processSteps.append(
      .init(
        step: step,
        fileStorage: fileStorage,
        inputPath: inputPath,
        outputPath: outputPath,
        pageWriteMode: pageWriteMode,
        siteMetadata: siteMetadata
      ))
    return self
  }

  @discardableResult
  public func run() throws -> Self {
    print("\(Date()) | Starting run")

    let readStart = DispatchTime.now()
    for step in processSteps {
      try step.runReaders()
    }

    let readEnd = DispatchTime.now()
    let readTime = readEnd.uptimeNanoseconds - readStart.uptimeNanoseconds
    print("\(Date()) | Finished readers in \(Double(readTime) / 1_000_000_000)s")

    let writeStart = DispatchTime.now()
    for step in processSteps {
      try step.runWriters()
    }

    let writeEnd = DispatchTime.now()
    let writeTime = writeEnd.uptimeNanoseconds - writeStart.uptimeNanoseconds
    print("\(Date()) | Finished writers \(Double(writeTime) / 1_000_000_000)s")

    return self
  }

  // Copies all unhandled files as-is to the output folder.
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
      try output.parent().mkpath()
      try input.copy(output)
    }

    let end = DispatchTime.now()
    let time = end.uptimeNanoseconds - start.uptimeNanoseconds
    print("\(Date()) | Finished copying static files in \(Double(time) / 1_000_000_000)s")

    return self
  }
}
