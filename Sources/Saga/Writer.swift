import PathKit
import Foundation

/// Writers turn an ``Item`` into a `String` using a "renderer", and write the resulting `String` to a file on disk.
///
/// To turn an ``Item`` into a `String`, a `Writer` uses a "renderer"; a function that knows how to turn a rendering context such as ``ItemRenderingContext`` into a `String`.
///
/// > Note: Saga does not come bundled with any renderers out of the box, instead you should install one such as [SagaSwimRenderer](https://github.com/loopwerk/SagaSwimRenderer) or [SagaStencilRenderer](https://github.com/loopwerk/SagaStencilRenderer).
public struct Writer<M: Metadata> {
  let run: (_ items: [Item<M>], _ allItems: [AnyItem], _ outputRoot: Path, _ outputPrefix: Path, _ fileIO: FileIO) throws -> Void
}

private extension Array {
  func chunked(into size: Int) -> [[Element]] {
    return stride(from: 0, to: count, by: size).map {
      Array(self[$0 ..< Swift.min($0 + size, count)])
    }
  }
}

public extension Writer {
  /// Writes a single ``Item`` to a single output file, using `Item.destination` as the destination path.
  static func itemWriter(_ renderer: @escaping (ItemRenderingContext<M>) throws -> String) -> Self {
    Writer { items, allItems, outputRoot, outputPrefix, fileIO in
      for item in items {
        let context = ItemRenderingContext(item: item, items: items, allItems: allItems)
        let stringToWrite = try renderer(context)
        try fileIO.write(outputRoot + item.relativeDestination, stringToWrite)
      }
    }
  }

  /// Writes an array of items into a single output file.
  static func listWriter(_ renderer: @escaping (ItemsRenderingContext<M>) throws -> String, output: Path = "index.html", paginate: Int? = nil, paginatedOutput: Path = "page/[page]/index.html") -> Self {
    return Self { items, allItems, outputRoot, outputPrefix, fileIO in
      try writePages(renderer: renderer, items: items, allItems: allItems, outputRoot: outputRoot, outputPrefix: outputPrefix, output: output, paginate: paginate, paginatedOutput: paginatedOutput, fileIO: fileIO) {
        return ItemsRenderingContext(items: $0, allItems: $1, paginator: $2, outputPath: $3)
      }
    }
  }

  /// Writes an array of items into multiple output files.
  ///
  /// Use this to partition an array of items into a dictionary of Items, with a custom key.
  ///
  /// The `output` path is a template where `[key]` will be replaced with the key used for the partition.
  /// Example: `articles/[key]/index.html`
  static func partitionedWriter<T>(_ renderer: @escaping (PartitionedRenderingContext<T, M>) throws -> String, output: Path = "[key]/index.html", paginate: Int? = nil, paginatedOutput: Path = "[key]/page/[page]/index.html", partitioner: @escaping ([Item<M>]) -> [T: [Item<M>]]) -> Self {
    return Self { items, allItems, outputRoot, outputPrefix, fileIO in
      let partitions = partitioner(items)

      for (key, itemsInPartition) in Array(partitions).sorted(by: {$0.0 < $1.0}) {
        let finishedOutputPath = Path(output.string.replacingOccurrences(of: "[key]", with: "\(key.slugified)"))
        let finishedPaginatedOutputPath = Path(paginatedOutput.string.replacingOccurrences(of: "[key]", with: "\(key.slugified)"))
        try writePages(renderer: renderer, items: itemsInPartition, allItems: allItems, outputRoot: outputRoot, outputPrefix: outputPrefix, output: finishedOutputPath, paginate: paginate, paginatedOutput: finishedPaginatedOutputPath, fileIO: fileIO) {
          return PartitionedRenderingContext(key: key, items: $0, allItems: $1, paginator: $2, outputPath: $3)
        }
      }
    }
  }

  /// A convenience version of `partitionedWriter` that splits items based on year.
  static func yearWriter(_ renderer: @escaping (PartitionedRenderingContext<Int, M>) throws -> String, output: Path = "[key]/index.html", paginate: Int? = nil, paginatedOutput: Path = "[key]/page/[page]/index.html") -> Self {
    let partitioner: ([Item<M>]) -> [Int: [Item<M>]] = { items in
      var itemsPerYear = [Int: [Item<M>]]()

      for item in items {
        let year = item.published.year
        if var itemsArray = itemsPerYear[year] {
          itemsArray.append(item)
          itemsPerYear[year] = itemsArray
        } else {
          itemsPerYear[year] = [item]
        }
      }

      return itemsPerYear
    }

    return partitionedWriter(renderer, output: output, paginate: paginate, paginatedOutput: paginatedOutput, partitioner: partitioner)
  }

  /// A convenience version of `partitionedWriter` that splits items based on tags.
  ///
  /// Tags can be any `[String]` array.
  static func tagWriter(_ renderer: @escaping (PartitionedRenderingContext<String, M>) throws -> String, output: Path = "tag/[key]/index.html", paginate: Int? = nil, paginatedOutput: Path = "tag/[key]/page/[page]/index.html", tags: @escaping (Item<M>) -> [String]) -> Self {
    let partitioner: ([Item<M>]) -> [String: [Item<M>]] = { items in
      var itemsPerTag = [String: [Item<M>]]()

      for item in items {
        for tag in tags(item) {
          if var itemArray = itemsPerTag[tag] {
            itemArray.append(item)
            itemsPerTag[tag] = itemArray
          } else {
            itemsPerTag[tag] = [item]
          }
        }
      }

      return itemsPerTag
    }

    return partitionedWriter(renderer, output: output, paginate: paginate, paginatedOutput: paginatedOutput, partitioner: partitioner)
  }
}

private extension Writer {
  static func writePages<Context>(renderer: @escaping (Context) throws -> String, items: [Item<M>], allItems: [AnyItem], outputRoot: Path, outputPrefix: Path, output: Path, paginate: Int?, paginatedOutput: Path, fileIO: FileIO, getContext: ([Item<M>], [AnyItem], Paginator?, Path) -> Context) throws {
    if let perPage = paginate {
      let ranges = items.chunked(into: perPage)
      let numberOfPages = ranges.count

      // First we write the first page to the "main" destination, for example /articles/index.html
      if let firstItems = ranges.first {
        let nextPage = Path(paginatedOutput.string.replacingOccurrences(of: "[page]", with: "2")).makeOutputPath(itemWriteMode: .keepAsFile)

        let paginator = Paginator(
          index: 1,
          itemsPerPage: perPage,
          numberOfPages: numberOfPages,
          previous: nil,
          next: numberOfPages > 1 ? (outputPrefix + nextPage) : nil
        )

        let context = getContext(firstItems, allItems, paginator, outputPrefix + output)
        let stringToWrite = try renderer(context)
        try fileIO.write(outputRoot + outputPrefix + output, stringToWrite)
      }

      // Then we write all the pages to their paginated paths, for example /articles/page/[page]/index.html
      for (index, items) in ranges.enumerated() {
        let currentPage = index + 1
        let previousPage = Path(paginatedOutput.string.replacingOccurrences(of: "[page]", with: "\(currentPage - 1)")).makeOutputPath(itemWriteMode: .keepAsFile)
        let nextPage = Path(paginatedOutput.string.replacingOccurrences(of: "[page]", with: "\(currentPage + 1)")).makeOutputPath(itemWriteMode: .keepAsFile)

        let paginator = Paginator(
          index: index + 1,
          itemsPerPage: perPage,
          numberOfPages: numberOfPages,
          previous: currentPage == 1 ? nil : (outputPrefix + previousPage),
          next: currentPage == numberOfPages ? nil : (outputPrefix + nextPage)
        )

        let finishedOutputPath = Path(paginatedOutput.string.replacingOccurrences(of: "[page]", with: "\(currentPage)"))
        let context = getContext(items, allItems, paginator, outputPrefix + finishedOutputPath)
        let stringToWrite = try renderer(context)
        try fileIO.write(outputRoot + outputPrefix + finishedOutputPath, stringToWrite)
      }
    } else {
      let context = getContext(items, allItems, nil, outputPrefix + output)
      let stringToWrite = try renderer(context)
      try fileIO.write(outputRoot + outputPrefix + output, stringToWrite)
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
