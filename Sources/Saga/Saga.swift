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

  /// Glob patterns to ignore during file watching in dev mode
  var ignoreChangesPatterns: [String] = [".DS_Store"]

  /// Why the current build was triggered.
  public internal(set) var buildReason: BuildReason = .initial

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

  /// Configure internationalization support.
  ///
  /// When enabled, Saga expects content to be organized in locale-prefixed folders
  /// (e.g. `en/articles/`, `nl/articles/`). Each `register()` call automatically fans out
  /// into per-locale processing steps.
  ///
  /// For a complete walkthrough, see <doc:Internationalization>.
  ///
  /// ```swift
  /// try await Saga(input: "content", output: "deploy")
  ///   .i18n(
  ///     locales: ["en", "nl"],
  ///     defaultLocale: "en",
  ///     localizedOutputFolders: ["articles": ["nl": "artikelen"]]
  ///   )
  ///   .register(
  ///     folder: "articles",
  ///     metadata: ArticleMetadata.self,
  ///     readers: [.parsleyMarkdownReader],
  ///     writers: [.itemWriter(swim(renderArticle))]
  ///   )
  ///   .run()
  /// ```
  ///
  /// - Parameters:
  ///   - locales: The supported locales (e.g. `["en", "nl"]`).
  ///   - defaultLocale: The default locale. Its content is written to the root unless `prefixDefaultLocaleOutputFolder` is `true`.
  ///   - prefixDefaultLocaleOutputFolder: Whether the default locale should also get a subdirectory prefix. Defaults to `false`.
  ///   - localizedOutputFolders: A mapping of content folder → [locale → output folder]. Allows output folder names
  ///     to differ from content folder names per locale. Locales not in the map use the original folder name.
  @discardableResult
  public func i18n(
    locales: [SagaLocale],
    defaultLocale: SagaLocale,
    prefixDefaultLocaleOutputFolder: Bool = false,
    localizedOutputFolders: [String: [SagaLocale: String]] = [:]
  ) -> Self {
    precondition(locales.contains(defaultLocale), "defaultLocale \"\(defaultLocale)\" must be included in locales \(locales)")
    precondition(steps.isEmpty, "i18n() must be called before register()")
    i18nConfig = I18NConfig(locales: locales, defaultLocale: defaultLocale, prefixDefaultLocaleOutputFolder: prefixDefaultLocaleOutputFolder, localizedOutputFolders: localizedOutputFolders)
    return self
  }

  /// Register a hook that runs before the read phase of each build cycle.
  ///
  /// For a CSS compilation example, see <doc:TailwindCSS>.
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
  /// For a search indexing example, see <doc:AddingSearch>.
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
  /// For a minification example, see <doc:HTMLMinification>.
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

  /// Add a glob pattern to ignore during file watching in dev mode.
  ///
  /// Use this to prevent unnecessary rebuilds when certain files change:
  ///
  /// ```swift
  /// try await Saga(input: "content", output: "deploy")
  ///   .ignoreChanges("output.css")
  ///   .ignoreChanges("*.tmp")
  ///   .register(...)
  ///   .run()
  /// ```
  @discardableResult
  public func ignoreChanges(_ pattern: String) -> Self {
    ignoreChangesPatterns.append(pattern)
    return self
  }

  @available(*, deprecated, renamed: "ignoreChanges")
  @discardableResult
  public func ignore(_ pattern: String) -> Self {
    ignoreChanges(pattern)
  }

  /// Execute all the registered steps.
  @discardableResult
  public func run() async throws -> Self {
    // Write config file so saga-cli can detect output path for serving
    writeConfigFile()

    // Check if this launch was triggered by a recompile
    readRecompileReason()

    // Run the pipeline
    try await build()

    // When launched by `saga dev`, watch for changes and rebuild
    if Saga.isDev, Saga.isCLI {
      signalParent(SIGUSR2)
      try await watchAndRebuild()
    }

    return self
  }
}
