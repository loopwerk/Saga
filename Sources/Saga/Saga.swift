import Foundation
import PathKit
import Stencil

public class Saga<SiteMetadata: Metadata> {
  public let rootPath: Path
  public let inputPath: Path
  public let outputPath: Path
  public let templates: Path
  public let siteMetadata: SiteMetadata

  public let fileStorage: [FileContainer]
  internal var processSteps = [AnyProcessStep]()

  public init(input: Path, output: Path, templates: Path, siteMetadata: SiteMetadata, originFilePath: StaticString = #file) throws {
    let originFile = Path("\(originFilePath)")
    rootPath = try originFile.resolveSwiftPackageFolder()
    inputPath = rootPath + input
    outputPath = rootPath + output
    self.templates = templates
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
  public func register<M: Metadata>(folder: Path? = nil, metadata: M.Type, readers: [Reader<M>], filter: @escaping ((Page<M>) -> Bool) = { _ in true }, writers: [Writer<M, SiteMetadata>]) throws -> Self {
    let step = ProcessStep(folder: folder, readers: readers, filter: filter, writers: writers)
    self.processSteps.append(
      .init(
        step: step,
        fileStorage: fileStorage,
        inputPath: inputPath,
        outputPath: outputPath,
        environment: getEnvironment(),
        siteMetadata: siteMetadata
      ))
    return self
  }

  @discardableResult
  public func run() throws -> Self {
    // First we run all the readers for all the steps, so that ALL the pages are available for all the writers.
    for step in processSteps {
      try step.runReaders()
    }

    for step in processSteps {
      try step.runWriters()
    }

    return self
  }

  // Copies all unhandled files as-is to the output folder.
  @discardableResult
  public func staticFiles() throws -> Self {
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

// The default read function
private extension Saga {
  func getEnvironment() -> Environment {
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
      guard let page = value as? AnyPage else {
        return value
      }
      var url = "/" + page.relativeDestination.string
      if url.hasSuffix("/index.html") {
        url.removeLast(10)
      }
      return url
    }

    ext.registerFilter("striptags") { (value: Any) in
      guard let text = value as? String else {
        return value
      }
      return text.withoutHtmlTags
    }

    ext.registerFilter("wordcount") { (value: Any) in
      guard let text = value as? String else {
        return value
      }
      return text.numberOfWords
    }

    ext.registerFilter("slugify") { (value: Any) in
      guard let text = value as? String else {
        return value
      }
      return text.slugify()
    }

    ext.registerFilter("escape") { (value: Any) in
      guard let text = value as? String else {
        return value
      }
      return text
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "&", with: "&amp;")
    }

    ext.registerFilter("truncate") { (value: Any, arguments: [Any?]) in
      guard let text = value as? String else {
        return value
      }
      let length = arguments.first as? Int ?? 255
      return text.prefix(length)
    }

    let templatePath = rootPath + templates
    return Environment(loader: FileSystemLoader(paths: [templatePath]), extensions: [ext])
  }
}

private extension String {
  var numberOfWords: Int {
    var count = 0
    let range = startIndex..<endIndex
    enumerateSubstrings(in: range, options: [.byWords, .substringNotRequired, .localized], { _, _, _, _ -> () in
      count += 1
    })
    return count
  }

  // This is a sloppy implementation but sadly `NSAttributedString(data:options:documentAttributes:)`
  // is not available in CoreFoundation.
  var withoutHtmlTags: String {
    return self
      .replacingOccurrences(of: "(?m)<pre><span></span><code>[\\s\\S]+?</code></pre>", with: "", options: .regularExpression, range: nil)
      .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
  }
}
