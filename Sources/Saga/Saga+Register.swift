import Foundation
import SagaPathKit

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
    write: @Sendable @escaping (Saga, _ stepItems: [AnyItem]) async throws -> Void,
    deferred: Bool = false
  ) -> Self {
    processSteps.append((
      read: { [self] in try await read(self) },
      write: { [self] stepItems in try await write(self, stepItems) },
      deferred: deferred
    ))
    return self
  }

  func addFileStep<M: Metadata>(
    folder: Path?,
    readers: [Reader],
    itemProcessor: (@Sendable (Item<M>) async -> Void)?,
    filter: @escaping @Sendable (Item<M>) -> Bool,
    claimExcludedItems: Bool,
    itemWriteMode: ItemWriteMode,
    sorting: @escaping @Sendable (Item<M>, Item<M>) -> Bool,
    writers: [Writer<M>]
  ) {
    register(
      read: { saga in
        // Filter to only files that match the folder (if any) and have a supported reader
        let relevant = saga.unhandledFiles.filter { file in
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
                  date: date ?? saga.fileIO.creationDate(file.path) ?? Date(),
                  created: saga.fileIO.creationDate(file.path) ?? Date(),
                  lastModified: saga.fileIO.modificationDate(file.path) ?? Date(),
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
              saga.handledPaths.insert(result.filePath)
            }

            if let item = result.item {
              items.append(item)
            }
          }

          return items
        }

        return items.sorted(by: sorting)
      },
      write: { saga, stepItems in
        let items = stepItems.compactMap { $0 as? Item<M> }
        let context = WriterContext(
          items: items,
          allItems: saga.allItems,
          outputRoot: saga.outputPath,
          outputPrefix: folder ?? Path(""),
          write: { try saga.processedWrite($0, $1) },
          resourcesByFolder: saga.resourcesByFolder()
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
