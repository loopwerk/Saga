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

/// Discover canonical subfolders across all locale-prefixed paths.
/// Returns paths without locale prefix, e.g., "articles/sub1" not "en/articles/sub1".
private func discoverLocaleAwareSubfolders(under folder: Path, from files: [(path: Path, relativePath: Path)], config: I18NConfig) -> Set<Path> {
  var canonical = Set<Path>()
  for locale in config.locales {
    let localePrefixed = Path(locale) + folder
    let subs = discoverSubfolders(under: localePrefixed, from: files)
    for sub in subs {
      // Strip locale prefix: "en/articles/sub1" → "articles/sub1"
      let stripped = String(sub.string.dropFirst(locale.count + 1))
      canonical.insert(Path(stripped))
    }
  }
  return canonical
}

/// Tags items with their locale and rewrites their output paths.
private func tagItemsWithLocale(_ items: [AnyItem], locale: String, config: I18NConfig) {
  let prefix = locale + "/"
  for item in items {
    if item.locale == nil {
      item.locale = locale
    }
    if !config.shouldPrefix(locale: locale), item.relativeDestination.string.hasPrefix(prefix) {
      item.relativeDestination = Path(String(item.relativeDestination.string.dropFirst(prefix.count)))
    }
  }
}

/// Tags items by filename suffix for `.filename` style i18n.
private func tagItemsByFilename(_ items: [AnyItem], config: I18NConfig, itemWriteMode: ItemWriteMode) {
  for item in items {
    let name = item.relativeSource.lastComponentWithoutExtension
    guard let locale = config.locales.first(where: { name.hasSuffix(".\($0)") }) else { continue }

    item.locale = locale
    let ext = item.relativeSource.extension ?? "md"
    let cleanName = String(name.dropLast(locale.count + 1))
    let cleanPath = item.relativeSource.parent() + Path(cleanName + "." + ext)
    var dest = cleanPath.makeOutputPath(itemWriteMode: itemWriteMode)
    if config.shouldPrefix(locale: locale) {
      dest = Path(locale) + dest
    }
    item.relativeDestination = dest
  }
}

/// Groups items by locale and returns (locale, items, outputPrefix) tuples for writer execution.
private func localeGroups<M: Metadata>(items: [Item<M>], outputPrefix: Path, saga: Saga) -> [(locale: String?, items: [Item<M>], outputPrefix: Path)] {
  guard let i18n = saga.i18nConfig else {
    return [(nil, items, outputPrefix)]
  }

  var groups: [(locale: String?, items: [Item<M>], outputPrefix: Path)] = []
  let itemsByLocale = Dictionary(grouping: items, by: { $0.locale ?? "" })

  for locale in i18n.locales {
    let localeItems = itemsByLocale[locale] ?? []
    guard !localeItems.isEmpty else { continue }
    let prefix = i18n.shouldPrefix(locale: locale) ? Path(locale) + outputPrefix : outputPrefix
    groups.append((locale, localeItems, prefix))
  }

  let independent = items.filter { $0.locale == nil }
  if !independent.isEmpty {
    groups.append((nil, independent, outputPrefix))
  }

  return groups
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
    write: { try saga.processedWrite($0, $1, locale: $2) },
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
  let files: [(path: Path, relativePath: Path)]
  let workingPath: Path // relative to inputPath
  var i18nConfig: I18NConfig?

  init(files: [(path: Path, relativePath: Path)], workingPath: Path, i18nConfig: I18NConfig? = nil) {
    self.files = files
    self.workingPath = workingPath
    self.i18nConfig = i18nConfig
  }

  /// Register a new pipeline step.
  ///
  /// - Parameters:
  ///   - folder: The folder (relative to `input`) to operate on. If `nil`, it operates on the `input` folder itself.
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

    // When `folder` ends with "/**", treat as nested (with a deprecation warning)
    if let folder, folder.string.hasSuffix("/**") {
      print("❕The '/**' folder suffix is deprecated. Use 'nested:' instead.")
      return register(
        folder: folder.parent(),
        nested: { nested in
          nested.register(
            metadata: M.self,
            readers: readers,
            itemProcessor: itemProcessor,
            filter: filter,
            claimExcludedItems: claimExcludedItems,
            itemWriteMode: itemWriteMode,
            sorting: effectiveSorting,
            writers: writers
          )
        }
      )
    }

    let effectiveFolder = workingPath + (folder ?? Path(""))

    if let nested {
      let parentReaders: [Reader]? = readers.isEmpty ? nil : readers

      // Discover subfolders at build-time, locale-aware when i18n is configured
      let subFolders: Set<Path> = if let i18n = i18nConfig, i18n.style == .directory {
        discoverLocaleAwareSubfolders(under: effectiveFolder, from: files, config: i18n)
      } else {
        discoverSubfolders(under: effectiveFolder, from: files)
      }

      // For each subfolder, create a child StepBuilder scoped to it.
      // Child steps are appended first (leaf-first), so they claim their files before the parent step runs.
      for subFolderPath in subFolders {
        let child = StepBuilder(files: files, workingPath: subFolderPath, i18nConfig: i18nConfig)
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
        outputPrefix: effectiveFolder
      ))

      return self
    }

    let subfolder = workingPath.string.isEmpty ? nil : Path(workingPath.lastComponent)
    nonisolated(unsafe) var items: [Item<M>] = []

    steps.append(PipelineStep(
      read: { saga in
        var allLocaleItems: [Item<M>] = []

        if let i18n = saga.i18nConfig, i18n.style == .directory {
          for locale in i18n.locales {
            let localeFolder = Path(locale) + effectiveFolder
            let localeItems: [Item<M>] = try await saga.readItems(
              folder: localeFolder,
              readers: readers,
              itemProcessor: itemProcessor,
              filter: filter,
              claimExcludedItems: claimExcludedItems,
              itemWriteMode: itemWriteMode,
              sorting: effectiveSorting
            )
            tagItemsWithLocale(localeItems, locale: locale, config: i18n)
            allLocaleItems.append(contentsOf: localeItems)
          }
        } else {
          allLocaleItems = try await saga.readItems(
            folder: effectiveFolder,
            readers: readers,
            itemProcessor: itemProcessor,
            filter: filter,
            claimExcludedItems: claimExcludedItems,
            itemWriteMode: itemWriteMode,
            sorting: effectiveSorting
          )
        }

        // For filename-style i18n, tag by filename suffix
        if let i18n = saga.i18nConfig, i18n.style == .filename {
          tagItemsByFilename(allLocaleItems, config: i18n, itemWriteMode: itemWriteMode)
        }

        items = allLocaleItems.sorted(by: effectiveSorting)
        return items
      },
      write: { saga in
        for group in localeGroups(items: items, outputPrefix: effectiveFolder, saga: saga) {
          try await executeWriters(items: group.items, writers: writers, saga: saga, outputPrefix: group.outputPrefix, subfolder: subfolder, locale: group.locale)
        }
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
    outputPrefix: Path
  ) -> PipelineStep {
    nonisolated(unsafe) var parentItems: [Item<M>] = []

    return PipelineStep(
      read: { saga in
        for subFolderPath in subFolders {
          if let i18n = saga.i18nConfig, i18n.style == .directory {
            // For directory-style i18n, create a parent item per locale per subfolder
            for locale in i18n.locales {
              let localeSubFolder = Path(locale) + subFolderPath
              let parentItem: Item<M>
              if let readers {
                let readItems: [Item<M>] = try await saga.readItems(
                  folder: localeSubFolder,
                  readers: readers,
                  itemProcessor: itemProcessor,
                  filter: filter,
                  claimExcludedItems: claimExcludedItems,
                  itemWriteMode: itemWriteMode,
                  sorting: sorting
                )
                guard let first = readItems.first else { continue }
                parentItem = first
              } else {
                let subfolderName = subFolderPath.lastComponent
                parentItem = Item<M>(
                  absoluteSource: saga.inputPath + localeSubFolder,
                  relativeSource: localeSubFolder,
                  relativeDestination: localeSubFolder + Path("index.html"),
                  title: subfolderName,
                  body: "",
                  date: Date(),
                  created: Date(),
                  lastModified: Date(),
                  metadata: try M(from: makeMetadataDecoder(for: [:]))
                )
              }

              tagItemsWithLocale([parentItem], locale: locale, config: i18n)

              // Wire children: match by locale-prefixed subfolder path
              let localeSubFolderPrefix = localeSubFolder.string + "/"
              let directChildren: [AnyItem] = saga.allItems.filter {
                $0.relativeSource.string.hasPrefix(localeSubFolderPrefix) && $0.parent == nil
              }
              parentItem.children = directChildren
              for child in directChildren {
                child.parent = parentItem
              }

              parentItems.append(parentItem)
            }
          } else {
            // Standard non-i18n (or filename-style) parent creation
            let parentItem: Item<M>
            if let readers {
              let readItems: [Item<M>] = try await saga.readItems(
                folder: subFolderPath,
                readers: readers,
                itemProcessor: itemProcessor,
                filter: filter,
                claimExcludedItems: claimExcludedItems,
                itemWriteMode: itemWriteMode,
                sorting: sorting
              )
              guard let first = readItems.first else { continue }
              parentItem = first
            } else {
              parentItem = Item<M>(
                absoluteSource: saga.inputPath + subFolderPath,
                relativeSource: subFolderPath,
                relativeDestination: subFolderPath + Path("index.html"),
                title: subFolderPath.lastComponent,
                body: "",
                date: Date(),
                created: Date(),
                lastModified: Date(),
                metadata: try M(from: makeMetadataDecoder(for: [:]))
              )
            }

            let subFolderPrefix = subFolderPath.string + "/"
            let directChildren: [AnyItem] = saga.allItems.filter {
              $0.relativeSource.string.hasPrefix(subFolderPrefix) && $0.parent == nil
            }

            parentItem.children = directChildren
            for child in directChildren {
              child.parent = parentItem
            }

            // For filename-style i18n, tag parent by filename suffix
            if let i18n = saga.i18nConfig, i18n.style == .filename {
              tagItemsByFilename([parentItem], config: i18n, itemWriteMode: itemWriteMode)
            }

            parentItems.append(parentItem)
          }
        }

        parentItems.sort(by: sorting)
        return parentItems
      },
      write: { saga in
        for group in localeGroups(items: parentItems, outputPrefix: outputPrefix, saga: saga) {
          try await executeWriters(items: group.items, writers: writers, saga: saga, outputPrefix: group.outputPrefix, subfolder: nil, locale: group.locale)
        }
      }
    )
  }
}
