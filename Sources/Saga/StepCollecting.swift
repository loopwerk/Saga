import Foundation
import SagaPathKit

/// Combines a folder override from a parent step with a step's own folder.
/// When both exist, appends the step folder to the override (relative scoping).
/// When only one exists, uses that one. Returns nil when both are nil.
private func resolveFolder(_ folderOverride: Path?, _ folder: Path?) -> Path? {
  if let folderOverride {
    if let folder {
      return folderOverride + folder
    }
    return folderOverride
  }
  return folder
}

public struct PipelineStep: @unchecked Sendable {
  let outputPrefix: Path
  let read: @Sendable (Saga, _ folderOverride: Path?) async throws -> [AnyItem]
  let write: @Sendable (Saga, _ stepItems: [AnyItem], _ outputPrefix: Path, _ subfolder: Path?) async throws -> Void
}

public protocol StepCollecting: AnyObject {
  var steps: [PipelineStep] { get set }
}

public class SubStepBuilder: @unchecked Sendable, StepCollecting {
  public var steps: [PipelineStep] = []
}

public extension StepCollecting {
  @discardableResult
  @preconcurrency
  func register<M: Metadata>(
    folder: Path? = nil,
    metadata: M.Type = EmptyMetadata.self,
    readers: [Reader] = [],
    itemProcessor: (@Sendable (Item<M>) async -> Void)? = nil,
    filter: @escaping @Sendable (Item<M>) -> Bool = { _ in true },
    claimExcludedItems: Bool = true,
    itemWriteMode: ItemWriteMode = .moveToSubfolder,
    sorting: @escaping @Sendable (Item<M>, Item<M>) -> Bool = { $0.date > $1.date },
    writers: [Writer<M>] = [],
    nested: ((SubStepBuilder) -> Void)? = nil
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
            itemWriteMode: itemWriteMode,
            sorting: sorting,
            writers: writers
          )
        }
      )
    }

    if let nested {
      let builder = SubStepBuilder()
      nested(builder)

      let parentReaders: [Reader]? = readers.isEmpty ? nil : readers
      let substeps = builder.steps

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

          var allParentItems: [Item<M>] = []
          var allSubstepItems: [AnyItem] = []

          for subFolder in subFolders {
            let subfolderName = try subFolder.relativePath(from: effectiveFolder)

            // Run substeps first (deepest-first) so they claim their files
            // before the parent reader runs on the same folder tree.
            var directChildren: [AnyItem] = []
            var allChildItems: [AnyItem] = []
            for substep in substeps {
              let items = try await substep.read(saga, subFolder)
              directChildren.append(contentsOf: items.filter { $0.parent == nil })
              allChildItems.append(contentsOf: items)
              allSubstepItems.append(contentsOf: items)
            }

            // Read or create parent item for this subfolder
            let parentItem: Item<M>
            if let parentReaders {
              let parentItems: [Item<M>] = try await saga.readItems(
                folder: subFolder,
                readers: parentReaders,
                itemProcessor: itemProcessor,
                filter: filter,
                claimExcludedItems: claimExcludedItems,
                itemWriteMode: itemWriteMode,
                sorting: sorting
              )
              guard let first = parentItems.first else { continue }
              parentItem = first
            } else {
              parentItem = Item<M>(
                absoluteSource: Path(""),
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

            allParentItems.append(parentItem)
          }

          // Return all items: parents + all nested children
          var allItems: [AnyItem] = allParentItems.sorted(by: sorting)
          allItems.append(contentsOf: allSubstepItems)
          return allItems
        },
        write: { saga, stepItems, outputPrefix, _ in
          // Parent items are the ones with children wired by the read closure
          let parentItems = stepItems.compactMap { $0 as? Item<M> }.filter { !$0.children.isEmpty }

          // Run outer (parent) writers
          if !writers.isEmpty {
            let context = WriterContext(
              items: parentItems,
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

          // Run substep writers scoped per subfolder
          for parentItem in parentItems {
            let subfolderName = try parentItem.relativeSource.relativePath(from: outputPrefix)
            let subOutputPrefix = outputPrefix + subfolderName

            for substep in substeps {
              let childItems = parentItem.children
              try await substep.write(saga, childItems, subOutputPrefix, subfolderName)
            }
          }
        }
      ))
      return self
    }

    steps.append(PipelineStep(
      outputPrefix: folder ?? Path(""),
      read: { saga, folderOverride in
        try await saga.readItems(
          folder: resolveFolder(folderOverride, folder),
          readers: readers,
          itemProcessor: itemProcessor,
          filter: filter,
          claimExcludedItems: claimExcludedItems,
          itemWriteMode: itemWriteMode,
          sorting: sorting
        )
      },
      write: { saga, stepItems, outputPrefix, subfolder in
        let items = stepItems.compactMap { $0 as? Item<M> }
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

  @discardableResult
  @preconcurrency
  func createPage(_ output: Path, using renderer: @Sendable @escaping (PageRenderingContext) async throws -> String) -> Self {
    steps.append(PipelineStep(
      outputPrefix: Path(""),
      read: { _, _ in [] },
      write: { saga, _, outputPrefix, _ in
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

  @discardableResult
  @preconcurrency
  func register<M: Metadata>(
    metadata: M.Type = EmptyMetadata.self,
    fetch: @escaping @Sendable () async throws -> [Item<M>],
    itemProcessor: (@Sendable (Item<M>) async -> Void)? = nil,
    sorting: @escaping @Sendable (Item<M>, Item<M>) -> Bool = { $0.date > $1.date },
    writers: [Writer<M>]
  ) -> Self {
    steps.append(PipelineStep(
      outputPrefix: Path(""),
      read: { _, _ in
        let items = try await fetch().sorted(by: sorting)
        if let itemProcessor {
          for item in items {
            await itemProcessor(item)
          }
        }
        return items
      },
      write: { saga, stepItems, outputPrefix, subfolder in
        let items = stepItems.compactMap { $0 as? Item<M> }
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

  @discardableResult
  @preconcurrency
  func register(write: @Sendable @escaping (Saga) async throws -> Void) -> Self {
    steps.append(PipelineStep(
      outputPrefix: Path(""),
      read: { _, _ in [] },
      write: { saga, _, _, _ in try await write(saga) }
    ))
    return self
  }
}
