import Foundation
import PathKit
import Stencil

public struct Saga {
  public let rootPath: Path
  public let inputPath: Path
  public let outputPath: Path

  public var fileStorage = [FileContainer]()

  public init(input: Path, output: Path, originFilePath: StaticString = #file) throws {
    let originFile = Path("\(originFilePath)")
    rootPath = try originFile.resolveSwiftPackageFolder()
    inputPath = rootPath + input
    outputPath = rootPath + output

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
}

// The default read function
public extension Saga {
  @discardableResult
  func read(folder: Path? = nil, metadata: Metadata.Type, readers: [Reader]) throws -> Self {
    var pages = [Page]()

    let unhandledFileWrappers = fileStorage.filter { $0.handled == false }

    for fileWrapper in unhandledFileWrappers {
      let relativePath = try fileWrapper.path.relativePath(from: inputPath)

      // Only work on files that match the folder (if any)
      if let folder = folder, !relativePath.string.starts(with: folder.string) {
        continue
      }

      // Pick the first reader that is able to work on this file, based on file extension
      guard let reader = readers.first(where: { $0.supportedExtensions.contains(relativePath.extension ?? "") }) else {
        continue
      }

      do {
        // Turn the file into a Page
        let page = try reader.convert(fileWrapper.path, metadata, relativePath)

        // Store the generated Page
        fileWrapper.page = page
        fileWrapper.handled = true
        pages.append(page)
      } catch {
        // Couldn't convert the file into a Page, probably because of missing metadata
        // We still mark it has handled, otherwise another, less specific, read step might
        // pick it up with an EmptyMetadata, turning a broken page suddenly into a working page,
        // which is probably not what you want.
        fileWrapper.handled = true
        print("❕File \(relativePath) failed conversion to Page<\(metadata.self)>, error: ", error)
        continue
      }
    }

    return self
  }
}

public extension Saga {
  // The default write function
  @discardableResult
  func write(templates: Path, writers: [Writer]) throws -> Self {
    let environment = getEnvironment(templatePath: rootPath + templates)

    for writer in writers {
      try writer.write(fileStorage.compactMap(\.page), { template, context, destination in
        try render(environment: environment, template: template, context: context, destination: destination)
      }, outputPath, "")
    }

    return self
  }

  // Copies all unhandled files as-is to the output folder.
  @discardableResult
  func staticFiles() throws -> Self {
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

    return self
  }
}

private extension Saga {
  func render(environment: Environment, template: Path, context: [String : Any], destination: Path) throws {
    let rendered = try environment.renderTemplate(name: template.string, context: context)
    try destination.parent().mkpath()
    try destination.write(rendered)
  }

  func getEnvironment(templatePath: Path) -> Environment {
    let ext = Extension()

    ext.registerFilter("date") { (value: Any?, arguments: [Any?]) in
      guard let date = value as? Date else {
        return value
      }

      let formatter = DateFormatter()
      formatter.dateFormat = arguments.first as? String ?? "yyyy-MM-dd"
      return formatter.string(from: date)
    }

    ext.registerFilter("url") { (value: Any) in
      guard let page = value as? Page else {
        return value
      }
      var url = "/" + page.relativeDestination.string
      if url.hasSuffix("/index.html") {
        url.removeLast(10)
      }
      return url
    }

    return Environment(loader: FileSystemLoader(paths: [templatePath]), extensions: [ext])
  }
}
