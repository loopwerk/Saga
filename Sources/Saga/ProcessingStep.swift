import Foundation
import PathKit

internal class ProcessStep<M: Metadata> {
  let folder: Path?
  let readers: [Reader<M>]
  let filter: (Item<M>) -> Bool
  let itemProcessor: ((Item<M>) async -> Void)?
  let writers: [Writer<M>]
  var items: [Item<M>]

  init(folder: Path?, readers: [Reader<M>], itemProcessor: ((Item<M>) async -> Void)?, filter: @escaping (Item<M>) -> Bool, writers: [Writer<M>]) {
    self.folder = folder
    self.readers = readers
    self.itemProcessor = itemProcessor
    self.filter = filter
    self.writers = writers
    self.items = []
  }
}

internal class AnyProcessStep {
  let runReaders: () async throws -> ()
  let runWriters: () throws -> ()

  init<M: Metadata>(step: ProcessStep<M>, fileStorage: [FileContainer], inputPath: Path, outputPath: Path, itemWriteMode: ItemWriteMode, fileIO: FileIO) {
    runReaders = {
      var items = [Item<M>]()

      let unhandledFileContainers = fileStorage.filter { $0.handled == false }

      for unhandledFileContainer in unhandledFileContainers {
        // Only work on files that match the folder (if any)
        if let folder = step.folder, !unhandledFileContainer.relativePath.string.starts(with: folder.string) {
          continue
        }

        // Pick the first reader that is able to work on this file, based on file extension
        guard let reader = step.readers.first(where: { $0.supportedExtensions.contains(unhandledFileContainer.path.extension ?? "") }) else {
          continue
        }

        // Mark it as handled so that another step that works on a less specific folder doesn't also try to read it
        unhandledFileContainer.handled = true

        do {
          // Turn the file into an Item
          let item = try await reader.convert(unhandledFileContainer.path, unhandledFileContainer.relativePath, unhandledFileContainer.relativePath.makeOutputPath(itemWriteMode: itemWriteMode))

          // Process the Item if there's an itemProcessor
          if let itemProcessor = step.itemProcessor {
            await itemProcessor(item)
          }
          
          // Store the generated Item if it passes the filter
          if step.filter(item) {
            unhandledFileContainer.item = item
            items.append(item)
          }
        } catch {
          // Couldn't convert the file into an Item, probably because of missing metadata
          // We still mark it has handled, otherwise another, less specific, read step might
          // pick it up with an EmptyMetadata, turning a broken item suddenly into a working item,
          // which is probably not what you want.
          print("❕File \(unhandledFileContainer.relativePath) failed conversion to Item<\(M.self)>, error: ", error)
          continue
        }
      }

      step.items = items.sorted(by: { left, right in left.published > right.published })
    }

    runWriters = {
      let allItems = fileStorage
        .compactMap(\.item)
        .sorted(by: { left, right in left.published > right.published })

      for writer in step.writers {
        try writer.run(step.items, allItems, fileStorage, outputPath, step.folder ?? "", fileIO)
      }
    }
  }
}
