import Foundation
import SagaPathKit

struct WriterContext<M: Metadata> {
  let items: [Item<M>]
  let allItems: [AnyItem]
  let outputRoot: Path
  let outputPrefix: Path
  let write: @Sendable (Path, String) throws -> Void
  let resourcesByFolder: [Path: [Path]]
  let subfolder: Path?
}

/// Writers turn an ``Item`` into a `String` using a "renderer", and write the resulting `String` to a file on disk.
///
/// To turn an ``Item`` into a `String`, a `Writer` uses a "renderer"; a function that knows how to turn a rendering context such as ``ItemRenderingContext`` into a `String`.
///
/// > Note: Saga does not come bundled with any renderers out of the box, instead you should install one such as [SagaSwimRenderer](https://github.com/loopwerk/SagaSwimRenderer) or [SagaStencilRenderer](https://github.com/loopwerk/SagaStencilRenderer).
public struct Writer<M: Metadata>: Sendable {
  let run: @Sendable (WriterContext<M>) async throws -> Void
}

private extension Array {
  func chunked(into size: Int) -> [[Element]] {
    return stride(from: 0, to: count, by: size).map {
      Array(self[$0 ..< Swift.min($0 + size, count)])
    }
  }
}

public extension Writer {
  /// Writes a single ``Item`` to a single output file, using `Item.relativeDestination` as the destination path.
  @preconcurrency
  static func itemWriter(_ renderer: @Sendable @escaping (ItemRenderingContext<M>) async throws -> String) -> Self {
    Writer { writerContext in
      try await withThrowingTaskGroup(of: Void.self) { group in
        for (index, item) in writerContext.items.enumerated() {
          group.addTask {
            // Resources are unhandled files in the same folder. These could be images for example, or other static files.
            let resources = writerContext.resourcesByFolder[item.relativeSource.parent()] ?? []
            let previous = index > 0 ? writerContext.items[index - 1] : nil
            let next = index < writerContext.items.count - 1 ? writerContext.items[index + 1] : nil
            let renderingContext = ItemRenderingContext(
              item: item,
              items: writerContext.items,
              allItems: writerContext.allItems,
              resources: resources,
              previous: previous,
              next: next,
              subfolder: writerContext.subfolder
            )
            let stringToWrite = try await renderer(renderingContext)

            try writerContext.write(
              writerContext.outputRoot + item.relativeDestination,
              stringToWrite
            )
          }
        }

        try await group.waitForAll()
      }
    }
  }

  /// Writes an array of items into a single output file.
  @preconcurrency
  static func listWriter(
    _ renderer: @Sendable @escaping (ItemsRenderingContext<M>) async throws -> String,
    output: Path = "index.html",
    paginate: Int? = nil,
    paginatedOutput: Path = "page/[page]/index.html"
  ) -> Self {
    Writer { writerContext in
      try await writePages(
        writerContext: writerContext,
        renderer: renderer,
        output: output,
        paginate: paginate,
        paginatedOutput: paginatedOutput
      ) {
        ItemsRenderingContext(items: $0, allItems: $1, paginator: $2, outputPath: $3, subfolder: writerContext.subfolder)
      }
    }
  }

  /// Writes an array of items into multiple output files.
  ///
  /// Use this to partition an array of items into a dictionary of Items, with a custom key.
  ///
  /// The `output` path is a template where `[key]` will be replaced with the key used for the partition.
  /// Example: `articles/[key]/index.html`
  @preconcurrency
  static func partitionedWriter<T>(
    _ renderer: @Sendable @escaping (PartitionedRenderingContext<T, M>) async throws -> String,
    output: Path = "[key]/index.html",
    paginate: Int? = nil,
    paginatedOutput: Path = "[key]/page/[page]/index.html",
    partitioner: @Sendable @escaping ([Item<M>]) -> [T: [Item<M>]]
  ) -> Self {
    Writer { writerContext in
      let partitions = partitioner(writerContext.items)

      try await withThrowingTaskGroup(of: Void.self) { group in
        for (key, itemsInPartition) in Array(partitions).sorted(by: { $0.0 < $1.0 }) {
          group.addTask {
            let finishedOutputPath = Path(output.string.replacingOccurrences(of: "[key]", with: "\(key.slugified)"))
            let finishedPaginatedOutputPath = Path(paginatedOutput.string.replacingOccurrences(of: "[key]", with: "\(key.slugified)"))
            let partitionContext = WriterContext(
              items: itemsInPartition,
              allItems: writerContext.allItems,
              outputRoot: writerContext.outputRoot,
              outputPrefix: writerContext.outputPrefix,
              write: writerContext.write,
              resourcesByFolder: writerContext.resourcesByFolder,
              subfolder: writerContext.subfolder
            )

            try await writePages(
              writerContext: partitionContext,
              renderer: renderer,
              output: finishedOutputPath,
              paginate: paginate,
              paginatedOutput: finishedPaginatedOutputPath
            ) {
              PartitionedRenderingContext(key: key, items: $0, allItems: $1, paginator: $2, outputPath: $3, subfolder: writerContext.subfolder)
            }
          }
        }

        try await group.waitForAll()
      }
    }
  }

  /// A convenience version of `partitionedWriter` that groups items by a key path.
  @preconcurrency
  static func groupedWriter<T: Hashable>(
    _ renderer: @Sendable @escaping (PartitionedRenderingContext<T, M>) async throws -> String,
    by keyPath: @Sendable @escaping (Item<M>) -> T,
    output: Path = "[key]/index.html",
    paginate: Int? = nil,
    paginatedOutput: Path = "[key]/page/[page]/index.html"
  ) -> Self {
    return partitionedWriter(renderer, output: output, paginate: paginate, paginatedOutput: paginatedOutput, partitioner: {
      Dictionary(grouping: $0, by: keyPath)
    })
  }

  /// A convenience version of `groupedWriter` that splits items based on year.
  @preconcurrency
  static func yearWriter(
    _ renderer: @Sendable @escaping (PartitionedRenderingContext<Int, M>) async throws -> String,
    output: Path = "[key]/index.html",
    paginate: Int? = nil,
    paginatedOutput: Path = "[key]/page/[page]/index.html"
  ) -> Self {
    return groupedWriter(renderer, by: \.date.year, output: output, paginate: paginate, paginatedOutput: paginatedOutput)
  }

  /// A convenience version of `partitionedWriter` that splits items based on tags.
  ///
  /// Tags can be any `[String]` array.
  @preconcurrency
  static func tagWriter(
    _ renderer: @Sendable @escaping (PartitionedRenderingContext<String, M>) async throws -> String,
    output: Path = "tag/[key]/index.html",
    paginate: Int? = nil,
    paginatedOutput: Path = "tag/[key]/page/[page]/index.html",
    tags: @Sendable @escaping (Item<M>) -> [String]
  ) -> Self {
    return partitionedWriter(renderer, output: output, paginate: paginate, paginatedOutput: paginatedOutput, partitioner: { items in
      var itemsPerTag = [String: [Item<M>]]()
      for item in items {
        for tag in tags(item) {
          itemsPerTag[tag, default: []].append(item)
        }
      }

      return itemsPerTag
    })
  }
}

private extension Writer {
  static func writePages<RenderContext>(
    writerContext: WriterContext<M>,
    renderer: @escaping @Sendable (RenderContext) async throws -> String,
    output: Path,
    paginate: Int?,
    paginatedOutput: Path,
    getRenderContext: @escaping @Sendable ([Item<M>], [AnyItem], Paginator?, Path) -> RenderContext
  ) async throws {
    if let perPage = paginate {
      let ranges = writerContext.items.chunked(into: perPage)
      let numberOfPages = ranges.count

      // First we write the first page to the "main" destination, for example /articles/index.html
      if let firstItems = ranges.first {
        let nextPage = Path(paginatedOutput.string.replacingOccurrences(of: "[page]", with: "2")).makeOutputPath(itemWriteMode: .keepAsFile)

        let paginator = Paginator(
          index: 1,
          itemsPerPage: perPage,
          numberOfPages: numberOfPages,
          previous: nil,
          next: numberOfPages > 1 ? (writerContext.outputPrefix + nextPage) : nil
        )

        let renderContext = getRenderContext(firstItems, writerContext.allItems, paginator, writerContext.outputPrefix + output)
        let stringToWrite = try await renderer(renderContext)
        try writerContext.write(writerContext.outputRoot + writerContext.outputPrefix + output, stringToWrite)
      }

      // Then we write all the pages to their paginated paths, for example /articles/page/[page]/index.html
      try await withThrowingTaskGroup(of: Void.self) { group in
        for (index, items) in ranges.enumerated() {
          group.addTask {
            let currentPage = index + 1
            let previousPage = Path(paginatedOutput.string.replacingOccurrences(of: "[page]", with: "\(currentPage - 1)")).makeOutputPath(itemWriteMode: .keepAsFile)
            let nextPage = Path(paginatedOutput.string.replacingOccurrences(of: "[page]", with: "\(currentPage + 1)")).makeOutputPath(itemWriteMode: .keepAsFile)

            let paginator = Paginator(
              index: currentPage,
              itemsPerPage: perPage,
              numberOfPages: numberOfPages,
              previous: currentPage == 1 ? nil : (writerContext.outputPrefix + previousPage),
              next: currentPage == numberOfPages ? nil : (writerContext.outputPrefix + nextPage)
            )

            let finishedOutputPath = Path(paginatedOutput.string.replacingOccurrences(of: "[page]", with: "\(currentPage)"))
            let renderContext = getRenderContext(items, writerContext.allItems, paginator, writerContext.outputPrefix + finishedOutputPath)
            let stringToWrite = try await renderer(renderContext)
            try writerContext.write(writerContext.outputRoot + writerContext.outputPrefix + finishedOutputPath, stringToWrite)
          }
        }
        try await group.waitForAll()
      }
    } else {
      // No pagination
      let renderContext = getRenderContext(writerContext.items, writerContext.allItems, nil, writerContext.outputPrefix + output)
      let stringToWrite = try await renderer(renderContext)
      try writerContext.write(writerContext.outputRoot + writerContext.outputPrefix + output, stringToWrite)
    }
  }
}

private let yearFormatter: DateFormatter = {
  let formatter = DateFormatter()
  formatter.dateFormat = "yyyy"
  return formatter
}()

private extension Date {
  var year: Int {
    return Int(yearFormatter.string(from: self))!
  }
}
