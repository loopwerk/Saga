import Foundation
import SagaPathKit

private struct FileReadResult<M: Metadata> {
  let filePath: Path
  let item: Item<M>?
  let claimFile: Bool
}

extension Saga {
  /// All generated pages, grouped by translation.
  var generatedPages: [[String: Path]] {
    guard i18nConfig != nil else {
      return writtenPages.map { ["": $0.path] }
    }

    var groups: [String: [String: Path]] = [:]
    for page in writtenPages {
      let key: String
      if let locale = page.locale {
        let prefix = locale + "/"
        key = page.path.string.hasPrefix(prefix) ? String(page.path.string.dropFirst(prefix.count)) : page.path.string
      } else {
        key = page.path.string
      }
      groups[key, default: [:]][page.locale ?? ""] = page.path
    }

    return Array(groups.values)
  }

  /// Write content to a file, applying any registered post-processors.
  /// Also tracks the relative path in ``writtenPages``.
  func processedWrite(_ destination: Path, _ content: String, locale: String? = nil) throws {
    let relativePath = try destination.relativePath(from: outputPath)
    writtenPagesLock.withLock { writtenPages.append((path: relativePath, locale: locale)) }

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
              title: partial.title ?? partial.frontmatter?["title"] ?? file.relativePath.lastComponentWithoutExtension,
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

  // MARK: - Translation linking

  func linkTranslations(items: [AnyItem], config: I18NConfig) {
    var groups: [String: [String: AnyItem]] = [:]

    for item in items {
      guard let locale = item.locale else { continue }
      let key = translationKey(for: item, config: config)
      groups[key, default: [:]][locale] = item
    }

    for (_, group) in groups where group.count > 1 {
      for (locale, item) in group {
        item.translations = group.filter { $0.key != locale }
      }
    }
  }

  func translationKey(for item: AnyItem, config: I18NConfig) -> String {
    // Strip locale prefix: en/articles/hello.md → articles/hello.md
    let source = item.relativeSource.string
    let components = source.split(separator: "/", maxSplits: 1)
    if components.count > 1, config.locales.contains(String(components[0])) {
      return String(components[1])
    }
    return source
  }
}
