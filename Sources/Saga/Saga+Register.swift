import Foundation
import SagaPathKit

extension Saga {
  func addFileStep<M: Metadata>(folder: Path?, readers: [Reader], itemProcessor: (@Sendable (Item<M>) async -> Void)?, filter: @escaping @Sendable (Item<M>) -> Bool, claimExcludedItems: Bool, itemWriteMode: ItemWriteMode, sorting: @escaping @Sendable (Item<M>, Item<M>) -> Bool, writers: [Writer<M>]) {
    let read: ReadStep = { [self] in
      // Filter to only files that match the folder (if any) and have a supported reader
      let relevant = unhandledFiles.filter { file in
        if let folder, !file.relativePath.string.starts(with: folder.string) {
          return false
        }
        return readers.contains { $0.supportedExtensions.contains(file.path.extension ?? "") }
      }

      // Process files in parallel with deterministic result ordering
      let items = try await withThrowingTaskGroup(of: (Int, Item<M>?, Bool).self) { group in
        for (index, file) in relevant.enumerated() {
          group.addTask {
            // Pick the first reader that is able to work on this file, based on file extension
            guard let reader = readers.first(where: { $0.supportedExtensions.contains(file.path.extension ?? "") }) else {
              return (index, nil, false)
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

              // Return the Item if it passes the filter, along with whether to mark the file as handled
              if filter(item) {
                return (index, item, !reader.copySourceFiles)
              } else {
                return (index, nil, claimExcludedItems)
              }
            } catch {
              // Couldn't convert the file into an Item, probably because of missing metadata.
              // We still mark it as handled, otherwise another, less specific, read step might
              // pick it up with an EmptyMetadata, turning a broken item suddenly into a working item,
              // which is probably not what you want.
              print("❕File \(file.relativePath) failed conversion to Item<\(M.self)>, error: ", error)
              return (index, nil, true)
            }
          }
        }

        // Collect results serially — safe to update handledPaths here
        var indexed: [(Int, Item<M>)] = []
        for try await (index, item, shouldHandle) in group {
          if shouldHandle {
            self.handledPaths.insert(relevant[index].path)
          }
          if let item {
            indexed.append((index, item))
          }
        }

        // Sort by original index to maintain deterministic order before date sorting
        return indexed.sorted { $0.0 < $1.0 }.map(\.1)
      }

      return items.sorted(by: sorting)
    }

    let write: WriteStep = { [self] stepItems in
      let items = stepItems.compactMap { $0 as? Item<M> }
      let context = WriterContext(
        items: items,
        allItems: allItems,
        outputRoot: outputPath,
        outputPrefix: folder ?? Path(""),
        write: { try self.processedWrite($0, $1) },
        resourcesByFolder: resourcesByFolder()
      )
      try await withThrowingTaskGroup(of: Void.self) { group in
        for writer in writers {
          group.addTask { try await writer.run(context) }
        }
        try await group.waitForAll()
      }
    }

    processSteps.append((read: read, write: write))
  }
}
