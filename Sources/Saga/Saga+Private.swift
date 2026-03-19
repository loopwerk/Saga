import Foundation
import SagaPathKit

private struct FileReadResult<M: Metadata> {
  let filePath: Path
  let item: Item<M>?
  let claimFile: Bool
}

private let logDateFormatter: DateFormatter = {
  let f = DateFormatter()
  f.dateFormat = "yyyy-MM-dd HH:mm:ss"
  return f
}()

extension Saga {
  func log(_ message: String) {
    print("\(logDateFormatter.string(from: Date())) | \(message)")
  }

  func elapsed(from start: DispatchTime) -> String {
    let nanos = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
    return String(format: "%.2fs", Double(nanos) / 1_000_000_000)
  }

  /// Write content to a file, applying any registered post-processors.
  /// Also tracks the relative path in ``generatedPages``.
  func processedWrite(_ destination: Path, _ content: String) throws {
    let relativePath = try destination.relativePath(from: outputPath)
    generatedPagesLock.withLock { generatedPages.append(relativePath) }

    let result = try postProcessors.reduce(content) { content, transform in try transform(content, relativePath) }
    try fileIO.write(destination, result)
  }

  /// Files not claimed by any processing step.
  var unhandledFiles: [(path: Path, relativePath: Path)] {
    files.filter { !handledPaths.contains($0.path) }
  }

  /// Unhandled files grouped by their relative parent folder.
  func resourcesByFolder() -> [Path: [Path]] {
    var result: [Path: [Path]] = [:]
    for file in unhandledFiles {
      result[file.relativePath.parent(), default: []].append(file.path)
    }
    return result
  }

  /// Reset mutable pipeline state between dev rebuilds.
  func reset() throws {
    allItems = []
    handledPaths = []
    generatedPages = []
    contentHashes = [:]

    // Re-scan input files (files may have been added/removed)
    let allFound = try fileIO.findFiles(inputPath).filter { $0.lastComponentWithoutExtension != ".DS_Store" }
    files = allFound.map { path in
      let relativePath = (try? path.relativePath(from: inputPath)) ?? Path("")
      return (path: path, relativePath: relativePath)
    }
  }

  /// Wait for SIGUSR1, then return.
  func waitForSignal() async {
    await withCheckedContinuation { continuation in
      let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
      source.setEventHandler {
        source.cancel()
        continuation.resume()
      }
      source.resume()
    }
  }

  /// Read files from disk using a Reader, turns them into Items
  func readItems<M: Metadata>(
    folder: Path?,
    readers: [Reader],
    itemProcessor: (@Sendable (Item<M>) async -> Void)?,
    filter: @escaping @Sendable (Item<M>) -> Bool,
    claimExcludedItems: Bool,
    itemWriteMode: ItemWriteMode,
    sorting: @escaping @Sendable (Item<M>, Item<M>) -> Bool,
    cacheKey: String
  ) async throws -> [Item<M>] {
    // Filter to only files that match the folder (if any) and have a supported reader
    let relevant = unhandledFiles.filter { file in
      if let folder, !folder.string.isEmpty, !file.relativePath.string.hasPrefix(folder.string + "/") {
        return false
      }
      return readers.contains { $0.supportedExtensions.contains(file.path.extension ?? "") }
    }

    // In-memory cache from previous dev rebuilds (keyed by relative path)
    let cache = readerCache[cacheKey] ?? [:]

    // Process files in parallel with deterministic result ordering
    let items = try await withThrowingTaskGroup(of: FileReadResult<M>.self) { group in
      for file in relevant {
        group.addTask {
          // Pick the first reader that is able to work on this file, based on file extension
          guard let reader = readers.first(where: { $0.supportedExtensions.contains(file.path.extension ?? "") }) else {
            return FileReadResult(filePath: file.path, item: nil, claimFile: false)
          }

          // Check in-memory cache: if the file hasn't changed, reuse the cached item
          let currentModDate = self.fileIO.modificationDate(file.path)
          if let cached = cache[file.relativePath.string] as? Item<M>,
             let currentModDate,
             cached.lastModified == currentModDate
          {
            if filter(cached) {
              return FileReadResult(filePath: file.path, item: cached, claimFile: !reader.copySourceFiles)
            } else {
              return FileReadResult(filePath: file.path, item: nil, claimFile: claimExcludedItems)
            }
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
              title: partial.frontmatter?["title"] ?? partial.title ?? file.relativePath.lastComponentWithoutExtension,
              body: partial.body,
              date: date ?? self.fileIO.creationDate(file.path) ?? Date(),
              created: self.fileIO.creationDate(file.path) ?? Date(),
              lastModified: self.fileIO.modificationDate(file.path) ?? Date(),
              metadata: metadata
            )

            // Override the output path if a slug is specified in frontmatter
            if let slug = partial.frontmatter?["slug"] {
              let parent = file.relativePath.parent()
              let slugPath = parent + Path(slug.slugified + "." + (file.relativePath.extension ?? "md"))
              item.relativeDestination = slugPath.makeOutputPath(itemWriteMode: itemWriteMode)
            }

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

      // Collect results serially — safe to update handledPaths and cache here
      var items: [Item<M>] = []
      var updatedCache: [String: AnyItem] = cache
      for try await result in group {
        if result.claimFile {
          self.handledPaths.insert(result.filePath)
        }

        if let item = result.item {
          items.append(item)
          updatedCache[item.relativeSource.string] = item
        }
      }

      self.readerCache[cacheKey] = updatedCache

      return items
    }

    return items.sorted(by: sorting)
  }
}
