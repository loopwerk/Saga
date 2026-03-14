import Foundation
import SagaPathKit

private func resolveFolder(_ folderOverride: Path?, _ folder: Path?) -> Path? {
  switch (folderOverride, folder) {
    case let (a?, b?): return a + b
    case let (a?, nil): return a
    case let (nil, b): return b
  }
}

struct PipelineStep: @unchecked Sendable {
  let outputPrefix: Path
  let read: @Sendable (Saga, _ folderOverride: Path?) async throws -> [AnyItem]
  let write: @Sendable (Saga, _ outputPrefix: Path, _ subfolder: Path?) async throws -> Void
}

/// A builder that collects pipeline steps.
public class StepBuilder: @unchecked Sendable {
  var steps: [PipelineStep] = []
  var folder: Path?

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
    sorting: @escaping @Sendable (Item<M>, Item<M>) -> Bool = { $0.date > $1.date },
    writers: [Writer<M>] = [],
    nested: (@Sendable (StepBuilder) -> Void)? = nil
  ) -> Self {
    // When folder ends with "/**", treat as nested with a deprecation warning.
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
            sorting: sorting,
            writers: writers
          )
        }
      )
    }

    if let nested {
      let parentReaders: [Reader]? = readers.isEmpty ? nil : readers

      // The tree is built during read: one child StepBuilder per discovered subfolder,
      // each with its own steps, items, and (recursively) children.
      nonisolated(unsafe) var items: [Item<M>] = []
      nonisolated(unsafe) var children: [StepBuilder] = []

      steps.append(PipelineStep(
        outputPrefix: folder ?? Path(""),
        read: { saga, folderOverride in
          guard let effectiveFolder = resolveFolder(folderOverride, folder) else { return [] }
          let baseFolderPrefix = effectiveFolder.string + "/"

          // Discover subfolders by finding immediate subdirectories under effectiveFolder
          let subFolders = Set(
            saga.files
              .filter { file in
                guard file.relativePath.string.hasPrefix(baseFolderPrefix) else { return false }
                let afterFolder = String(file.relativePath.string.dropFirst(baseFolderPrefix.count))
                return afterFolder.contains("/")
              }
              .map { file -> Path in
                let afterFolder = String(file.relativePath.string.dropFirst(baseFolderPrefix.count))
                let subfolderName = String(afterFolder.prefix(while: { $0 != "/" }))
                return effectiveFolder + Path(subfolderName)
              }
          )
          .sorted(by: { $0.string < $1.string })

          var allDescendants: [AnyItem] = []

          for subFolder in subFolders {
            let subfolderName = try subFolder.relativePath(from: effectiveFolder)

            // Instantiate fresh substeps for this subfolder from the template
            let child = StepBuilder()
            nested(child)

            // Run substeps first (deepest-first) so they claim their files
            // before the parent reader runs on the same folder tree.
            var directChildren: [AnyItem] = []
            for step in child.steps {
              let stepItems = try await step.read(saga, subFolder)
              directChildren.append(contentsOf: stepItems.filter { $0.parent == nil })
              allDescendants.append(contentsOf: stepItems)
            }

            // Read or create parent item for this subfolder
            let parentItem: Item<M>
            if let parentReaders {
              let readItems: [Item<M>] = try await saga.readItems(
                folder: subFolder,
                readers: parentReaders,
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
                absoluteSource: saga.inputPath + subFolder,
                relativeSource: subFolder,
                relativeDestination: (subFolder + Path("index.html")),
                title: subfolderName.lastComponent,
                body: "",
                date: directChildren.first?.date ?? Date(),
                created: directChildren.first?.created ?? Date(),
                lastModified: directChildren.first?.lastModified ?? Date(),
                metadata: try M(from: makeMetadataDecoder(for: [:]))
              )
            }

            // Wire parent/child relationships (only direct children, not all descendants)
            parentItem.children = directChildren
            for child in directChildren {
              child.parent = parentItem
            }

            child.folder = subfolderName
            items.append(parentItem)
            children.append(child)
          }

          items.sort(by: sorting)

          // Return all items: this level + all descendants (for saga.allItems)
          var result: [AnyItem] = items
          result.append(contentsOf: allDescendants)
          return result
        },
        write: { saga, outputPrefix, _ in
          // Run outer writers with this level's items
          if !writers.isEmpty {
            let context = WriterContext(
              items: items,
              allItems: saga.allItems,
              outputRoot: saga.outputPath,
              outputPrefix: outputPrefix,
              write: { try saga.processedWrite($0, $1) },
              resourcesByFolder: saga.resourcesByFolder(),
              subfolder: nil
            )
            try await withThrowingTaskGroup(of: Void.self) { group in
              for writer in writers {
                group.addTask { try await writer.run(context) }
              }
              try await group.waitForAll()
            }
          }

          // Each child StepBuilder has its own steps with its own items
          for child in children {
            let subOutputPrefix = outputPrefix + child.folder!

            for step in child.steps {
              try await step.write(saga, subOutputPrefix, child.folder!)
            }
          }
        }
      ))
      return self
    }

    nonisolated(unsafe) var items: [Item<M>] = []

    steps.append(PipelineStep(
      outputPrefix: folder ?? Path(""),
      read: { saga, folderOverride in
        items = try await saga.readItems(
          folder: resolveFolder(folderOverride, folder),
          readers: readers,
          itemProcessor: itemProcessor,
          filter: filter,
          claimExcludedItems: claimExcludedItems,
          itemWriteMode: itemWriteMode,
          sorting: sorting
        )
        return items
      },
      write: { saga, outputPrefix, subfolder in
        let context = WriterContext(
          items: items,
          allItems: saga.allItems,
          outputRoot: saga.outputPath,
          outputPrefix: outputPrefix,
          write: { try saga.processedWrite($0, $1) },
          resourcesByFolder: saga.resourcesByFolder(),
          subfolder: subfolder
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
          for writer in writers {
            group.addTask { try await writer.run(context) }
          }
          try await group.waitForAll()
        }
      }
    ))
    return self
  }

  /// Register a pipeline step that fetches items programmatically instead of reading from files.
  ///
  /// - Parameters:
  ///   - metadata: The metadata type used for the pipeline step. You can use ``EmptyMetadata`` if you don't need any custom metadata (which is the default value).
  ///   - fetch: An async function that returns an array of items.
  ///   - itemProcessor: A function to modify each fetched ``Item`` as you see fit.
  ///   - sorting: A comparison function used to sort items. Defaults to date descending (newest first).
  ///   - writers: The writers that will be used by this step.
  /// - Returns: The instance itself, so you can chain further calls onto it.
  @discardableResult
  @preconcurrency
  public func register<M: Metadata>(
    metadata: M.Type = EmptyMetadata.self,
    fetch: @escaping @Sendable () async throws -> [Item<M>],
    itemProcessor: (@Sendable (Item<M>) async -> Void)? = nil,
    sorting: @escaping @Sendable (Item<M>, Item<M>) -> Bool = { $0.date > $1.date },
    writers: [Writer<M>]
  ) -> Self {
    nonisolated(unsafe) var items: [Item<M>] = []

    steps.append(PipelineStep(
      outputPrefix: Path(""),
      read: { _, _ in
        items = try await fetch().sorted(by: sorting)
        if let itemProcessor {
          for item in items {
            await itemProcessor(item)
          }
        }
        return items
      },
      write: { saga, outputPrefix, subfolder in
        let context = WriterContext(
          items: items,
          allItems: saga.allItems,
          outputRoot: saga.outputPath,
          outputPrefix: outputPrefix,
          write: { try saga.processedWrite($0, $1) },
          resourcesByFolder: [:],
          subfolder: subfolder
        )
        try await withThrowingTaskGroup(of: Void.self) { group in
          for writer in writers {
            group.addTask { try await writer.run(context) }
          }
          try await group.waitForAll()
        }
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
      outputPrefix: Path(""),
      read: { _, _ in [] },
      write: { saga, _, _ in try await write(saga) }
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
      outputPrefix: Path(""),
      read: { _, _ in [] },
      write: { saga, outputPrefix, _ in
        let fullOutput = outputPrefix + output
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
}
