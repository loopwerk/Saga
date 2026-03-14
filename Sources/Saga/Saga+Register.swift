import Foundation
import SagaPathKit

/// Configuration for a nested registration within a parent `register` call.
///
/// Create instances using the static ``register(metadata:readers:itemProcessor:filter:itemWriteMode:sorting:writers:)`` method.
public struct NestedRegistration<C: Metadata>: Sendable {
  let readers: [Reader]
  let metadata: C.Type
  let itemProcessor: (@Sendable (Item<C>) async -> Void)?
  let filter: @Sendable (Item<C>) -> Bool
  let itemWriteMode: ItemWriteMode
  let sorting: @Sendable (Item<C>, Item<C>) -> Bool
  let writers: [Writer<C>]

  @preconcurrency
  public static func register(
    metadata: C.Type = EmptyMetadata.self,
    readers: [Reader],
    itemProcessor: (@Sendable (Item<C>) async -> Void)? = nil,
    filter: @escaping @Sendable (Item<C>) -> Bool = { _ in true },
    itemWriteMode: ItemWriteMode = .moveToSubfolder,
    sorting: @escaping @Sendable (Item<C>, Item<C>) -> Bool = { $0.date > $1.date },
    writers: [Writer<C>]
  ) -> NestedRegistration<C> {
    NestedRegistration(
      readers: readers,
      metadata: metadata,
      itemProcessor: itemProcessor,
      filter: filter,
      itemWriteMode: itemWriteMode,
      sorting: sorting,
      writers: writers
    )
  }
}

private struct FileReadResult<M: Metadata> {
  let filePath: Path
  let item: Item<M>?
  let claimFile: Bool
}

extension Saga {
  @discardableResult
  @preconcurrency
  func register(
    read: @Sendable @escaping (Saga) async throws -> [AnyItem],
    write: @Sendable @escaping (Saga, _ stepItems: [AnyItem]) async throws -> Void
  ) -> Self {
    processSteps.append((
      read: { [self] in try await read(self) },
      write: { [self] stepItems in try await write(self, stepItems) }
    ))
    return self
  }

  func readItems<M: Metadata>(
    folder: Path?,
    readers: [Reader],
    itemProcessor: (@Sendable (Item<M>) async -> Void)?,
    filter: @escaping @Sendable (Item<M>) -> Bool,
    claimExcludedItems: Bool,
    itemWriteMode: ItemWriteMode,
    sorting: @escaping @Sendable (Item<M>, Item<M>) -> Bool
  ) async throws -> [Item<M>] {
    // Filter to only files that match the folder (if any) and have a supported reader
    let relevant = unhandledFiles.filter { file in
      if let folder, !file.relativePath.string.starts(with: folder.string) {
        return false
      }
      return readers.contains { $0.supportedExtensions.contains(file.path.extension ?? "") }
    }

    // Process files in parallel with deterministic result ordering
    let items = try await withThrowingTaskGroup(of: FileReadResult<M>.self) { group in
      for file in relevant {
        group.addTask {
          // Pick the first reader that is able to work on this file, based on file extension
          guard let reader = readers.first(where: { $0.supportedExtensions.contains(file.path.extension ?? "") }) else {
            return FileReadResult(filePath: file.path, item: nil, claimFile: false)
          }

          do {
            // Use the Reader to convert the contents of the file to HTML
            let partial = try await reader.convert(file.path)

            // Then we try to decode the frontmatter (which is just a [String: String] dict) to proper metadata
            let decoder = makeMetadataDecoder(for: partial.frontmatter ?? [:])
            let date = try resolveDate(from: decoder)
            let metadata = try M(from: decoder)

            // Create the Item instance
            let item = Item(
              absoluteSource: file.path,
              relativeSource: file.relativePath,
              relativeDestination: file.relativePath.makeOutputPath(itemWriteMode: itemWriteMode),
              title: partial.title ?? file.relativePath.lastComponentWithoutExtension,
              body: partial.body,
              date: date ?? self.fileIO.creationDate(file.path) ?? Date(),
              created: self.fileIO.creationDate(file.path) ?? Date(),
              lastModified: self.fileIO.modificationDate(file.path) ?? Date(),
              metadata: metadata
            )

            // Process the Item if there's an itemProcessor
            if let itemProcessor {
              await itemProcessor(item)
            }

            if filter(item) {
              return FileReadResult(filePath: file.path, item: item, claimFile: !reader.copySourceFiles)
            } else {
              return FileReadResult(filePath: file.path, item: nil, claimFile: claimExcludedItems)
            }
          } catch {
            // Couldn't convert the file into an Item, probably because of missing metadata.
            // We still mark it as handled, otherwise another, less specific, read step might
            // pick it up with an EmptyMetadata, turning a broken item suddenly into a working item,
            // which is probably not what you want.
            print("❕File \(file.relativePath) failed conversion to Item<\(M.self)>, error: ", error)
            return FileReadResult(filePath: file.path, item: nil, claimFile: true)
          }
        }
      }

      // Collect results serially — safe to update handledPaths here
      var items: [Item<M>] = []
      for try await result in group {
        if result.claimFile {
          self.handledPaths.insert(result.filePath)
        }

        if let item = result.item {
          items.append(item)
        }
      }

      return items
    }

    return items.sorted(by: sorting)
  }

  func addNestedStep<M: Metadata, C: Metadata>(
    folder: Path,
    parentReaders: [Reader]?,
    parentItemProcessor: (@Sendable (Item<M>) async -> Void)?,
    parentFilter: @escaping @Sendable (Item<M>) -> Bool,
    claimExcludedItems: Bool,
    parentItemWriteMode: ItemWriteMode,
    parentSorting: @escaping @Sendable (Item<M>, Item<M>) -> Bool,
    parentWriters: [Writer<M>],
    nested: NestedRegistration<C>
  ) {
    // Shared between read and write closures; safe because they run sequentially per step.
    nonisolated(unsafe) var nestedItemsBySubfolder: [(subfolder: Path, items: [Item<C>])] = []

    register(
      read: { saga in
        let baseFolderPrefix = folder.string + "/"
        let nestedExtensions = Set(nested.readers.flatMap(\.supportedExtensions))

        // Discover subfolders that contain files matching the nested readers
        let subFolders = Set(
          saga.files
            .filter { file in
              guard file.relativePath.string.hasPrefix(baseFolderPrefix) else { return false }
              return nestedExtensions.contains(file.path.extension ?? "")
            }
            .map { $0.relativePath.parent() }
        )
        .filter { $0 != folder }
        .sorted(by: { $0.string < $1.string })

        var allParentItems: [Item<M>] = []
        nestedItemsBySubfolder = []

        for subFolder in subFolders {
          let subfolderName = try subFolder.relativePath(from: folder)

          // Read nested (child) items for this subfolder
          let childItems: [Item<C>] = try await saga.readItems(
            folder: subFolder,
            readers: nested.readers,
            itemProcessor: nested.itemProcessor,
            filter: nested.filter,
            claimExcludedItems: true,
            itemWriteMode: nested.itemWriteMode,
            sorting: nested.sorting
          )

          nestedItemsBySubfolder.append((subfolder: subfolderName, items: childItems))

          // Read or create parent item for this subfolder
          let parentItem: Item<M>
          if let parentReaders {
            // Read real parent items from this subfolder
            let parentItems: [Item<M>] = try await saga.readItems(
              folder: subFolder,
              readers: parentReaders,
              itemProcessor: parentItemProcessor,
              filter: parentFilter,
              claimExcludedItems: claimExcludedItems,
              itemWriteMode: parentItemWriteMode,
              sorting: parentSorting
            )
            guard let first = parentItems.first else { continue }
            parentItem = first
          } else {
            // Create a fake parent item for this subfolder
            let fakeItem = Item<M>(
              absoluteSource: Path(""),
              relativeSource: subFolder,
              relativeDestination: (subFolder + Path("index.html")),
              title: subfolderName.lastComponent,
              body: "",
              date: childItems.first?.date ?? Date(),
              created: childItems.first?.created ?? Date(),
              lastModified: childItems.first?.lastModified ?? Date(),
              metadata: try M(from: makeMetadataDecoder(for: [:]))
            )
            parentItem = fakeItem
          }

          // Wire parent/child relationships
          parentItem.children = childItems
          for child in childItems {
            child.parent = parentItem
          }

          allParentItems.append(parentItem)
        }

        // Return all items: parents + all nested children
        var allItems: [AnyItem] = allParentItems.sorted(by: parentSorting)
        for (_, items) in nestedItemsBySubfolder {
          allItems.append(contentsOf: items)
        }
        return allItems
      },
      write: { saga, stepItems in
        let parentItems = stepItems.compactMap { $0 as? Item<M> }.filter { $0.parent == nil }

        // Run outer (parent) writers
        if !parentWriters.isEmpty {
          let context = WriterContext(
            items: parentItems,
            allItems: saga.allItems,
            outputRoot: saga.outputPath,
            outputPrefix: folder,
            write: { try saga.processedWrite($0, $1) },
            resourcesByFolder: saga.resourcesByFolder(),
            subfolder: nil
          )
          try await withThrowingTaskGroup(of: Void.self) { group in
            for writer in parentWriters {
              group.addTask { try await writer.run(context) }
            }
            try await group.waitForAll()
          }
        }

        // Run nested writers scoped per subfolder
        if !nested.writers.isEmpty {
          for subfolderData in nestedItemsBySubfolder {
            let childItems = subfolderData.items
            let context = WriterContext(
              items: childItems,
              allItems: saga.allItems,
              outputRoot: saga.outputPath,
              outputPrefix: folder + subfolderData.subfolder,
              write: { try saga.processedWrite($0, $1) },
              resourcesByFolder: saga.resourcesByFolder(),
              subfolder: subfolderData.subfolder
            )
            try await withThrowingTaskGroup(of: Void.self) { group in
              for writer in nested.writers {
                group.addTask { try await writer.run(context) }
              }
              try await group.waitForAll()
            }
          }
        }
      }
    )
  }

  func addFileStep<M: Metadata>(
    folder: Path?,
    readers: [Reader],
    itemProcessor: (@Sendable (Item<M>) async -> Void)?,
    filter: @escaping @Sendable (Item<M>) -> Bool,
    claimExcludedItems: Bool,
    itemWriteMode: ItemWriteMode,
    sorting: @escaping @Sendable (Item<M>, Item<M>) -> Bool,
    writers: [Writer<M>],
    subfolder: Path? = nil
  ) {
    register(
      read: { saga in
        try await saga.readItems(
          folder: folder,
          readers: readers,
          itemProcessor: itemProcessor,
          filter: filter,
          claimExcludedItems: claimExcludedItems,
          itemWriteMode: itemWriteMode,
          sorting: sorting
        )
      },
      write: { saga, stepItems in
        let items = stepItems.compactMap { $0 as? Item<M> }
        let context = WriterContext(
          items: items,
          allItems: saga.allItems,
          outputRoot: saga.outputPath,
          outputPrefix: folder ?? Path(""),
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
    )
  }
}
