import Foundation
import SagaPathKit

struct SagaConfig: Codable {
  let input: String
  let output: String
}

private struct FileReadResult<M: Metadata> {
  let filePath: Path
  let item: Item<M>?
  let claimFile: Bool
}

extension Saga {
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

  /// Link items across locales by matching their source paths (after stripping the locale prefix).
  ///
  /// For example, `en/articles/hello.md` and `nl/articles/hello.md` share the translation key
  /// `articles/hello.md`, so they become translations of each other.
  func linkTranslations() {
    // Group items by their translation key (source path without the locale prefix)
    var groups: [String: [AnyItem]] = [:]
    for item in allItems {
      guard let locale = item.locale else { continue }
      let key = translationKey(for: item.relativeSource, locale: locale)
      groups[key, default: []].append(item)
    }

    // Wire up translations
    for (_, items) in groups where items.count > 1 {
      for item in items {
        for other in items where other !== item {
          if let otherLocale = other.locale {
            item.translations[otherLocale] = other
          }
        }
      }
    }
  }

  /// Strip the locale prefix from a source path to get the translation key.
  private func translationKey(for path: Path, locale: String) -> String {
    let prefix = locale + "/"
    let str = path.string
    if str.hasPrefix(prefix) {
      return String(str.dropFirst(prefix.count))
    }
    return str
  }

  /// Rewrite a relative path for i18n output.
  ///
  /// Files inside a locale folder (e.g. `en/static/style.css`) have the locale prefix
  /// stripped and are optionally re-prefixed based on whether the locale should be in a subdirectory.
  /// Files outside locale folders are copied as-is.
  func i18nOutputPath(for relativePath: Path, config: I18NConfig) -> Path {
    let str = relativePath.string
    for locale in config.locales {
      let prefix = locale + "/"
      if str.hasPrefix(prefix) {
        let stripped = String(str.dropFirst(prefix.count))
        if config.shouldPrefix(locale: locale) {
          return Path(locale) + Path(stripped)
        } else {
          return Path(stripped)
        }
      }
    }
    return relativePath
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

  /// Signal the parent process (saga-cli).
  /// - SIGUSR1: Swift source changed, please recompile and relaunch.
  /// - SIGUSR2: Content rebuild done, reload browsers.
  func signalParent(_ signal: Int32) {
    kill(getppid(), signal)
  }

  /// Write a config file to `.build/saga-config.json` so saga-cli can detect output path for serving.
  func writeConfigFile() {
    let config = SagaConfig(
      input: (try? inputPath.relativePath(from: rootPath))?.string ?? "content",
      output: (try? outputPath.relativePath(from: rootPath))?.string ?? "deploy"
    )

    let configPath = rootPath + ".build/saga-config.json"
    if let data = try? JSONEncoder().encode(config) {
      try? data.write(to: URL(fileURLWithPath: configPath.string))
    }
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
