import Foundation
import SagaPathKit

/// Discover immediate subdirectories of `folder` by inspecting file paths.
private func discoverSubfolders(under folder: Path, from files: [(path: Path, relativePath: Path)]) -> Set<Path> {
  let depth = folder.components.count
  return Set(
    files.compactMap { file -> Path? in
      let components = file.relativePath.components
      guard components.count > depth + 1 else { return nil }
      guard Array(components.prefix(depth)) == folder.components else { return nil }
      return folder + Path(components[depth])
    }
  )
}

/// Tags items with their locale and rewrites their output paths for i18n.
private func addLocaleToItems(_ items: [AnyItem], locale: String, config: I18NConfig, readFolder: Path, outputPrefix: Path) {
  let readPrefix = readFolder.string.isEmpty ? "" : readFolder.string + "/"
  let outputPrefixStr = outputPrefix.string.isEmpty ? "" : outputPrefix.string + "/"

  for item in items {
    item.locale = locale

    // Rewrite relativeDestination: replace the read folder prefix with the output prefix
    let dest = item.relativeDestination.string
    if !readPrefix.isEmpty, dest.hasPrefix(readPrefix) {
      item.relativeDestination = Path(outputPrefixStr + String(dest.dropFirst(readPrefix.count)))
    } else if readPrefix.isEmpty {
      item.relativeDestination = Path(outputPrefixStr + dest)
    }
  }
}

/// Runs writers with a WriterContext built from the given parameters.
private func executeWriters<M: Metadata>(
  items: [Item<M>],
  writers: [Writer<M>],
  saga: Saga,
  outputPrefix: Path,
  subfolder: Path?,
  locale: String?
) async throws {
  guard !writers.isEmpty else { return }

  let context = WriterContext(
    items: items,
    allItems: saga.allItems,
    outputRoot: saga.outputPath,
    outputPrefix: outputPrefix,
    write: { try saga.processedWrite($0, $1) },
    resourcesByFolder: saga.resourcesByFolder(),
    subfolder: subfolder,
    locale: locale
  )
  try await withThrowingTaskGroup(of: Void.self) { group in
    for writer in writers {
      group.addTask { try await writer.run(context) }
    }
    try await group.waitForAll()
  }
}

struct PipelineStep: @unchecked Sendable {
  let read: @Sendable (Saga) async throws -> [AnyItem]
  let write: @Sendable (Saga) async throws -> Void
}

/// A builder that collects pipeline steps.
public class StepBuilder: @unchecked Sendable {
  var steps: [PipelineStep] = []
  var files: [(path: Path, relativePath: Path)]
  let workingPath: Path // relative to inputPath, without locale prefix
  /// i18n configuration, or `nil` when i18n is not enabled.
  public var i18nConfig: I18NConfig?
  let locale: String? // when set, this builder is scoped to a specific locale
  let localizedOutputFolder: [String: String]? // locale → output folder name

  init(
    files: [(path: Path, relativePath: Path)],
    workingPath: Path,
    i18nConfig: I18NConfig? = nil,
    locale: String? = nil,
    localizedOutputFolder: [String: String]? = nil
  ) {
    self.files = files
    self.workingPath = workingPath
    self.i18nConfig = i18nConfig
    self.locale = locale
    self.localizedOutputFolder = localizedOutputFolder
  }

  /// Compute the output folder for a given locale.
  ///
  /// When `localizedOutputFolder` contains a mapping for the locale, use that.
  /// Otherwise, use the original folder name.
  private func outputFolder(for locale: String, folder: Path) -> Path {
    if let mapping = localizedOutputFolder, let localized = mapping[locale] {
      return Path(localized)
    }
    return folder
  }

  /// Register a new pipeline step.
  ///
  /// - Parameters:
  ///   - folder: The folder (relative to `input`) to operate on. If `nil`, it operates on the `input` folder itself.
  ///   - localizedOutputFolder: A mapping of locale to output folder name. When i18n is configured, this allows
  ///     the output folder to differ from the content folder per locale. Locales not in the map use the original `folder` name.
  ///   - metadata: The metadata type used for the pipeline step. You can use ``EmptyMetadata`` if you don't need any custom metadata (which is the default value).
  ///   - readers: The readers that will be used by this step.
  ///   - itemProcessor: A function to modify the generated ``Item`` as you see fit.
  ///   - filter: A filter to only include certain items from the input folder.
  ///   - claimExcludedItems: When an item is excluded by the `filter`, should this step claim it? If true (the default), excluded items won't be available to subsequent pipeline steps.
  ///   - itemWriteMode: The ``ItemWriteMode`` used by this step.
  ///   - sorting: A comparison function used to sort items. Defaults to date descending (newest first).
  ///   - writers: The writers that will be used by this step.
  ///   - nested: An optional closure to register nested substeps that run within each subfolder.
  /// - Returns: The instance itself, so you can chain further calls onto it.
  @discardableResult
  @preconcurrency
  public func register<M: Metadata>(
    folder: Path? = nil,
    localizedOutputFolder: [String: String]? = nil,
    metadata: M.Type = EmptyMetadata.self,
    readers: [Reader] = [],
    itemProcessor: (@Sendable (Item<M>) async -> Void)? = nil,
    filter: @escaping @Sendable (Item<M>) -> Bool = { _ in true },
    claimExcludedItems: Bool = true,
    itemWriteMode: ItemWriteMode = .moveToSubfolder,
    sorting: (@Sendable (Item<M>, Item<M>) -> Bool)? = nil,
    writers: [Writer<M>] = [],
    nested: (@Sendable (StepBuilder) -> Void)? = nil
  ) -> Self {
    // For nested steps we default to sorting by filename, otherwise we default to sorting by date
    let effectiveSorting: @Sendable (Item<M>, Item<M>) -> Bool = switch (sorting, nested) {
      case (let s?, _): s
      case (nil, _?): { $0.relativeSource.string < $1.relativeSource.string }
      case (nil, nil): { $0.date > $1.date }
    }

    // When i18n is configured and not yet locale-scoped, fan out into per-locale steps
    if let i18n = i18nConfig, locale == nil {
      for locale in i18n.locales {
        let localeBuilder = StepBuilder(
          files: files,
          workingPath: workingPath,
          i18nConfig: i18nConfig,
          locale: locale,
          localizedOutputFolder: localizedOutputFolder ?? self.localizedOutputFolder
        )
        localeBuilder.register(
          folder: folder,
          metadata: metadata,
          readers: readers,
          itemProcessor: itemProcessor,
          filter: filter,
          claimExcludedItems: claimExcludedItems,
          itemWriteMode: itemWriteMode,
          sorting: effectiveSorting,
          writers: writers,
          nested: nested
        )
        steps.append(contentsOf: localeBuilder.steps)
      }
      return self
    }

    let effectiveFolder = workingPath + (folder ?? Path(""))

    // When locale-scoped, the read folder includes the locale prefix
    let readFolder = locale.map { Path($0) + effectiveFolder } ?? effectiveFolder

    // Compute the output prefix: locale prefix (if needed) + localized folder name
    let localizedFolder = locale.map { outputFolder(for: $0, folder: effectiveFolder) } ?? effectiveFolder
    let outputPrefix: Path = if let locale, let i18n = i18nConfig, i18n.shouldPrefix(locale: locale) {
      Path(locale) + localizedFolder
    } else {
      localizedFolder
    }

    if let nested {
      let parentReaders: [Reader]? = readers.isEmpty ? nil : readers

      let rawSubFolders = discoverSubfolders(under: readFolder, from: files)

      // Convert to canonical paths (strip locale prefix if locale-scoped)
      let subFolders: Set<Path> = if locale != nil {
        Set(rawSubFolders.map { Path($0.components.dropFirst().joined(separator: "/")) })
      } else {
        rawSubFolders
      }

      // For each subfolder, create a child StepBuilder scoped to it.
      // Child steps are appended first (leaf-first), so they claim their files before the parent step runs.
      for subFolderPath in subFolders {
        let child = StepBuilder(
          files: files,
          workingPath: subFolderPath,
          i18nConfig: i18nConfig,
          locale: locale,
          localizedOutputFolder: localizedOutputFolder ?? self.localizedOutputFolder
        )
        nested(child)
        steps.append(contentsOf: child.steps)
      }

      // Parent step: creates/reads parent items and wires parent/child relationships.
      steps.append(parentStep(
        subFolders: subFolders,
        readers: parentReaders,
        itemProcessor: itemProcessor,
        filter: filter,
        claimExcludedItems: claimExcludedItems,
        itemWriteMode: itemWriteMode,
        sorting: effectiveSorting,
        writers: writers,
        readFolder: readFolder,
        outputPrefix: outputPrefix,
        cacheKey: "reader-\(locale ?? "")-\(steps.count)"
      ))

      return self
    }

    let subfolder = workingPath.string.isEmpty ? nil : Path(workingPath.lastComponent)
    nonisolated(unsafe) var items: [Item<M>] = []

    steps.append(PipelineStep(
      read: { [locale, steps] saga in
        items = try await saga.readItems(
          folder: readFolder,
          readers: readers,
          itemProcessor: itemProcessor,
          filter: filter,
          claimExcludedItems: claimExcludedItems,
          itemWriteMode: itemWriteMode,
          sorting: effectiveSorting,
          cacheKey: "reader-\(locale ?? "")-\(steps.count)"
        )

        if let locale, let i18n = saga.i18nConfig {
          addLocaleToItems(items, locale: locale, config: i18n, readFolder: readFolder, outputPrefix: outputPrefix)
        }

        return items
      },
      write: { [locale] saga in
        try await executeWriters(items: items, writers: writers, saga: saga, outputPrefix: outputPrefix, subfolder: subfolder, locale: locale)
      }
    ))

    return self
  }

  /// Register a pipeline step that fetches items programmatically instead of reading from files.
  ///
  /// When `SAGA_CACHE_DIR` is set (which `saga dev` does automatically), fetched items are
  /// cached to disk so that subsequent rebuilds skip the fetch. Pass `nil` for `cacheKey` to
  /// disable caching (useful while developing the fetch function itself).
  ///
  /// - Parameters:
  ///   - metadata: The metadata type used for the pipeline step. You can use ``EmptyMetadata`` if you don't need any custom metadata (which is the default value).
  ///   - fetch: An async function that returns an array of items.
  ///   - cacheKey: The cache key for storing fetched items. Defaults to the metadata type name. Pass `nil` to disable caching.
  ///   - itemProcessor: A function to modify each fetched ``Item`` as you see fit.
  ///   - sorting: A comparison function used to sort items. Defaults to date descending (newest first).
  ///   - writers: The writers that will be used by this step.
  /// - Returns: The instance itself, so you can chain further calls onto it.
  @discardableResult
  @preconcurrency
  public func register<M: Metadata>(
    metadata: M.Type = EmptyMetadata.self,
    fetch: @escaping @Sendable () async throws -> [Item<M>],
    cacheKey: String? = String(describing: M.self),
    itemProcessor: (@Sendable (Item<M>) async -> Void)? = nil,
    sorting: @escaping @Sendable (Item<M>, Item<M>) -> Bool = { $0.date > $1.date },
    writers: [Writer<M>]
  ) -> Self {
    nonisolated(unsafe) var items: [Item<M>] = []

    steps.append(PipelineStep(
      read: { saga in
        if let cacheKey, let cachedItems: [Item<M>] = try? saga.loadCachedItems(key: cacheKey) {
          print("💡Using cached \(cacheKey) items")
          items = cachedItems
        } else {
          items = try await fetch().sorted(by: sorting)
          if let cacheKey {
            saga.cacheItems(items, key: cacheKey)
          }
        }
        if let itemProcessor {
          for item in items {
            await itemProcessor(item)
          }
        }
        return items
      },
      write: { saga in
        try await executeWriters(items: items, writers: writers, saga: saga, outputPrefix: Path(""), subfolder: nil, locale: nil)
      }
    ))

    return self
  }

  /// Register a custom write-only step.
  ///
  /// Use this for logic outside the standard pipeline:
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
    steps.append(PipelineStep(
      read: { _ in [] },
      write: { saga in try await write(saga) }
    ))

    return self
  }

  /// Create a page that is driven purely by a template.
  ///
  /// Use this for pages such as a homepage showing the latest articles,
  /// a search page, or a 404 page. The renderer receives a ``PageRenderingContext`` with access to all items
  /// across all pipeline steps.
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
    steps.append(PipelineStep(
      read: { _ in [] },
      write: { [workingPath] saga in
        let fullOutput = workingPath + output
        let context = PageRenderingContext(
          allItems: saga.allItems,
          outputPath: fullOutput,
          generatedPages: saga.generatedPages
        )
        let string = try await renderer(context)
        try saga.processedWrite(saga.outputPath + fullOutput, string)
      }
    ))

    return self
  }

  /// Creates a parent step that reads/creates parent items for each subfolder
  /// and wires parent/child relationships. By the time this step runs,
  /// child items are already in saga.allItems.
  @preconcurrency
  private func parentStep<M: Metadata>(
    subFolders: Set<Path>,
    readers: [Reader]?,
    itemProcessor: (@Sendable (Item<M>) async -> Void)?,
    filter: @escaping @Sendable (Item<M>) -> Bool,
    claimExcludedItems: Bool,
    itemWriteMode: ItemWriteMode,
    sorting: @escaping @Sendable (Item<M>, Item<M>) -> Bool,
    writers: [Writer<M>],
    readFolder: Path,
    outputPrefix: Path,
    cacheKey: String
  ) -> PipelineStep {
    nonisolated(unsafe) var parentItems: [Item<M>] = []

    return PipelineStep(
      read: { [locale] saga in
        for subFolderPath in subFolders {
          let readPath = locale.map { Path($0) + subFolderPath } ?? subFolderPath

          let parentItem: Item<M>
          if let readers {
            let readItems: [Item<M>] = try await saga.readItems(
              folder: readPath,
              readers: readers,
              itemProcessor: itemProcessor,
              filter: filter,
              claimExcludedItems: claimExcludedItems,
              itemWriteMode: itemWriteMode,
              sorting: sorting,
              cacheKey: cacheKey
            )
            guard let first = readItems.first else { continue }
            parentItem = first
          } else {
            parentItem = Item<M>(
              absoluteSource: saga.inputPath + readPath,
              relativeSource: readPath,
              relativeDestination: readPath + Path("index.html"),
              title: subFolderPath.lastComponent,
              body: "",
              date: Date(),
              created: Date(),
              lastModified: Date(),
              metadata: try M(from: makeMetadataDecoder(for: [:]))
            )
          }

          if let locale, let i18n = saga.i18nConfig {
            addLocaleToItems([parentItem], locale: locale, config: i18n, readFolder: readFolder, outputPrefix: outputPrefix)
          }

          // Wire children: match by the read path (which includes locale prefix)
          let childPrefix = readPath.string + "/"
          let directChildren: [AnyItem] = saga.allItems.filter {
            $0.relativeSource.string.hasPrefix(childPrefix) && $0.parent == nil
          }
          parentItem.children = directChildren
          for child in directChildren {
            child.parent = parentItem
          }

          parentItems.append(parentItem)
        }

        parentItems.sort(by: sorting)
        return parentItems
      },
      write: { [locale] saga in
        try await executeWriters(items: parentItems, writers: writers, saga: saga, outputPrefix: outputPrefix, subfolder: nil, locale: locale)
      }
    )
  }
}
