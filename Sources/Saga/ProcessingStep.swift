import Foundation
import PathKit

class ProcessStep<M: Metadata> {
  let folder: Path?
  let readers: [Reader]
  let filter: (Item<M>) -> Bool
  let filteredOutItemsAreHandled: Bool
  let itemProcessor: ((Item<M>) async -> Void)?
  let writers: [Writer<M>]
  var items: [Item<M>]

  init(folder: Path?, readers: [Reader], itemProcessor: ((Item<M>) async -> Void)?, filter: @escaping (Item<M>) -> Bool, filteredOutItemsAreHandled: Bool, writers: [Writer<M>]) {
    self.folder = folder
    self.readers = readers
    self.itemProcessor = itemProcessor
    self.filter = filter
    self.filteredOutItemsAreHandled = filteredOutItemsAreHandled
    self.writers = writers
    items = []
  }
}

class AnyProcessStep {
  let runReaders: () async throws -> Void
  let runWriters: () async throws -> Void

  init<M: Metadata>(step: ProcessStep<M>, fileStorage: [FileContainer], inputPath: Path, outputPath: Path, itemWriteMode: ItemWriteMode, fileIO: FileIO) {
    runReaders = {
      let unhandledFileContainers = fileStorage.filter { $0.handled == false }

      // Filter to only files that match the folder (if any) and have a supported reader
      let relevantContainers = unhandledFileContainers.filter { container in
        // Check folder match
        if let folder = step.folder, !container.relativePath.string.starts(with: folder.string) {
          return false
        }

        // Check if any reader supports this file extension
        return step.readers.contains { $0.supportedExtensions.contains(container.path.extension ?? "") }
      }

      // Process files in parallel with deterministic result ordering
      let items = try await withThrowingTaskGroup(of: (Int, Item<M>?).self) { group in
        for (index, container) in relevantContainers.enumerated() {
          group.addTask {
            // Pick the first reader that is able to work on this file, based on file extension
            guard let reader = step.readers.first(where: { $0.supportedExtensions.contains(container.path.extension ?? "") }) else {
              return (index, nil)
            }

            do {
              // Use the Reader to convert the contents of the file to HTML
              let partialItem = try await reader.convert(container.path)

              // Then we try to decode the frontmatter (which is just a [String: String] dict) to proper metadata
              let decoder = makeMetadataDecoder(for: partialItem.frontmatter ?? [:])
              let date = try resolveDate(from: decoder)
              let metadata = try M(from: decoder)

              // Create the Item instance
              let item = Item(
                absoluteSource: container.path,
                relativeSource: container.relativePath,
                relativeDestination: container.relativePath.makeOutputPath(itemWriteMode: itemWriteMode),
                title: partialItem.title ?? container.relativePath.lastComponentWithoutExtension,
                body: partialItem.body,
                date: date ?? fileIO.creationDate(container.path) ?? Date(),
                created: fileIO.creationDate(container.path) ?? Date(),
                lastModified: fileIO.modificationDate(container.path) ?? Date(),
                metadata: metadata
              )

              // Process the Item if there's an itemProcessor
              if let itemProcessor = step.itemProcessor {
                await itemProcessor(item)
              }

              // Store the generated Item if it passes the filter
              if step.filter(item) {
                container.handled = !reader.copySourceFiles
                container.item = item
                return (index, item)
              } else {
                if step.filteredOutItemsAreHandled {
                  container.handled = true
                }
                return (index, nil)
              }
            } catch {
              // Couldn't convert the file into an Item, probably because of missing metadata
              // We still mark it has handled, otherwise another, less specific, read step might
              // pick it up with an EmptyMetadata, turning a broken item suddenly into a working item,
              // which is probably not what you want.
              print("❕File \(container.relativePath) failed conversion to Item<\(M.self)>, error: ", error)
              container.handled = true
              return (index, nil)
            }
          }
        }

        // Collect all successful items in deterministic order
        var indexedResults: [(Int, Item<M>)] = []
        for try await(index, item) in group {
          if let item = item {
            indexedResults.append((index, item))
          }
        }

        // Sort by original index to maintain deterministic order before date sorting
        return indexedResults.sorted(by: { $0.0 < $1.0 }).map(\.1)
      }

      step.items = items.sorted(by: { left, right in left.date > right.date })
    }

    runWriters = {
      let allItems = fileStorage
        .compactMap(\.item)
        .sorted(by: { left, right in left.date > right.date })

      try await withThrowingTaskGroup(of: Void.self) { group in
        for writer in step.writers {
          group.addTask {
            try await writer.run(step.items, allItems, fileStorage, outputPath, step.folder ?? "", fileIO)
          }
        }
        try await group.waitForAll()
      }
    }
  }
}
