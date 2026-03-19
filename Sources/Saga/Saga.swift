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
  var generatedPages: [Path] = []
  let generatedPagesLock = NSLock()

  /// Post processors
  var postProcessors: [@Sendable (String, Path) throws -> String] = []

  /// Hooks
  var beforeReadHooks: [@Sendable (Saga) async throws -> Void] = []
  var afterWriteHooks: [@Sendable (Saga) async throws -> Void] = []

  /// In-memory reader cache that survives between dev rebuilds
  var readerCache: [String: [String: AnyItem]] = [:]

  public init(input: Path, output: Path = "deploy", fileIO: FileIO = .diskAccess, originFilePath: StaticString = #filePath) throws {
    let originFile = Path("\(originFilePath)")
    let rootPath = try fileIO.resolveSwiftPackageFolder(originFile)

    self.rootPath = rootPath
    inputPath = self.rootPath + input
    outputPath = self.rootPath + output
    self.fileIO = fileIO

    // Find all files in the source folder (filter out .DS_Store)
    let allFound = try fileIO.findFiles(inputPath).filter { $0.lastComponentWithoutExtension != ".DS_Store" }
    let computedFiles = allFound.map { path in
      let relativePath = (try? path.relativePath(from: rootPath + input)) ?? Path("")
      return (path: path, relativePath: relativePath)
    }

    super.init(files: computedFiles, workingPath: Path(""))
  }

  /// Register a hook that runs before the read phase of each build cycle.
  ///
  /// Use this for pre-build steps like CSS compilation:
  /// ```swift
  /// try await Saga(input: "content", output: "deploy")
  ///   .beforeRead { _ in
  ///     try await tailwind.run(input: "content/static/input.css", output: "content/static/output.css")
  ///   }
  ///   .register(...)
  ///   .run()
  /// ```
  @discardableResult
  @preconcurrency
  public func beforeRead(_ hook: @Sendable @escaping (Saga) async throws -> Void) -> Self {
    beforeReadHooks.append(hook)
    return self
  }

  /// Register a hook that runs after the write phase of each build cycle.
  ///
  /// Use this for post-build steps like search indexing:
  /// ```swift
  /// try await Saga(input: "content", output: "deploy")
  ///   .register(...)
  ///   .afterWrite { saga in
  ///     // run pagefind, etc.
  ///   }
  ///   .run()
  /// ```
  @discardableResult
  @preconcurrency
  public func afterWrite(_ hook: @Sendable @escaping (Saga) async throws -> Void) -> Self {
    afterWriteHooks.append(hook)
    return self
  }

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

  /// Execute all the registered steps.
  @discardableResult
  public func run() async throws -> Self {
    // In dev mode, ignore SIGUSR1 at the process level so DispatchSource can handle it
    if Saga.isDev {
      signal(SIGUSR1, SIG_IGN)
    }

    while true {
      let totalStart = DispatchTime.now()
      log("Starting run")

      if !beforeReadHooks.isEmpty {
        let start = DispatchTime.now()
        for hook in beforeReadHooks {
          try await hook(self)
        }

        log("Finished beforeRead hooks in \(elapsed(from: start))")
      }

      // Run all the readers for all the steps sequentially to ensure proper order,
      // which turns raw content into Items, and stores them within the step.
      let readStart = DispatchTime.now()
      for step in steps {
        let items = try await step.read(self)
        allItems.append(contentsOf: items)
      }

      log("Finished read phase in \(elapsed(from: readStart))")

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

      log("Finished copying static files in \(elapsed(from: copyStart))")

      // Make Saga.hashed() work
      setupHashFunction()

      // Run all writers sequentially
      // processedWrite tracks generated paths automatically.
      let writeStart = DispatchTime.now()
      for step in steps {
        try await step.write(self)
      }

      log("Finished write phase in \(elapsed(from: writeStart))")

      // Copy hashed versions of files that were referenced via Saga.hashed()
      try copyHashedFiles()

      if !afterWriteHooks.isEmpty {
        let start = DispatchTime.now()
        for hook in afterWriteHooks {
          try await hook(self)
        }

        log("Finished afterWrite hooks in \(elapsed(from: start))")
      }

      log("All done in \(elapsed(from: totalStart))")

      // In dev mode, signal the CLI that the build is done, then wait for SIGUSR1
      if Saga.isDev {
        // Signal the parent process (saga dev) that the build completed
        if let pidString = ProcessInfo.processInfo.environment["SAGA_DEV_PID"],
           let pid = Int32(pidString)
        {
          kill(pid, SIGUSR2)
        }

        await waitForSignal()
        try reset()
        continue
      }

      return self
    } // while true
  }
}
