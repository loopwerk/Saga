import PathKit
import Foundation

public struct ItemRenderingContext<M: Metadata, SiteMetadata: Metadata> {
  public let item: Item<M>
  public let items: [Item<M>]
  public let allItems: [AnyItem]
  public let siteMetadata: SiteMetadata
}

public struct ItemsRenderingContext<M: Metadata, SiteMetadata: Metadata> {
  public let items: [Item<M>]
  public let allItems: [AnyItem]
  public let siteMetadata: SiteMetadata
  public let paginator: Paginator?
}

public typealias ContextKey = CustomStringConvertible & Comparable
public struct PartitionedRenderingContext<T: ContextKey, M: Metadata, SiteMetadata: Metadata> {
  public let key: T
  public let items: [Item<M>]
  public let allItems: [AnyItem]
  public let siteMetadata: SiteMetadata
  public let paginator: Paginator?
}

public struct Writer<M: Metadata, SiteMetadata: Metadata> {
  let run: ([Item<M>], [AnyItem], SiteMetadata, Path, Path, FileIO) throws -> Void
}

private extension Array {
  func chunked(into size: Int) -> [[Element]] {
    return stride(from: 0, to: count, by: size).map {
      Array(self[$0 ..< Swift.min($0 + size, count)])
    }
  }
}

public extension Writer {
  /// Writes a single Item to a single output file, using Item.destination as the destination path
  static func itemWriter(_ renderer: @escaping (ItemRenderingContext<M, SiteMetadata>) throws -> String) -> Self {
    Writer { items, allItems, siteMetadata, outputRoot, outputPrefix, fileIO in
      for item in items {
        let context = ItemRenderingContext(item: item, items: items, allItems: allItems, siteMetadata: siteMetadata)
        let node = try renderer(context)
        try fileIO.write(outputRoot + item.relativeDestination, node)
      }
    }
  }

  /// Writes an array of Items into a single output file.
  /// As such, it needs an output path, for example "articles/index.html".
  static func listWriter(_ renderer: @escaping (ItemsRenderingContext<M, SiteMetadata>) throws -> String, output: Path = "index.html", paginate: Int? = nil, paginatedOutput: Path = "page/[page]/index.html") -> Self {
    return Self { items, allItems, siteMetadata, outputRoot, outputPrefix, fileIO in
      try writePages(renderer: renderer, items: items, allItems: allItems, siteMetadata: siteMetadata, outputRoot: outputRoot, outputPrefix: outputPrefix, output: output, paginate: paginate, paginatedOutput: paginatedOutput, fileIO: fileIO) {
        return ItemsRenderingContext(items: $0, allItems: $1, siteMetadata: $2, paginator: $3)
      }
    }
  }

  /// Writes an array of Items into multiple output files.
  /// Use this to partition an array of Items into a dictionary of Items, with a custom key.
  /// The output path is a template where [key] will be replaced with the key used for the partition.
  /// Example: "articles/[key]/index.html"
  static func partitionedWriter<T>(_ renderer: @escaping (PartitionedRenderingContext<T, M, SiteMetadata>) throws -> String, output: Path = "[key]/index.html", paginate: Int? = nil, paginatedOutput: Path = "[key]/page/[page]/index.html", partitioner: @escaping ([Item<M>]) -> [T: [Item<M>]]) -> Self {
    return Self { items, allItems, siteMetadata, outputRoot, outputPrefix, fileIO in
      let partitions = partitioner(items)

      for (key, itemsInPartition) in Array(partitions).sorted(by: {$0.0 < $1.0}) {
        let finishedOutput = Path(output.string.replacingOccurrences(of: "[key]", with: "\(key.slugified)"))
        let finishedPaginatedOutput = Path(paginatedOutput.string.replacingOccurrences(of: "[key]", with: "\(key.slugified)"))
        try writePages(renderer: renderer, items: itemsInPartition, allItems: allItems, siteMetadata: siteMetadata, outputRoot: outputRoot, outputPrefix: outputPrefix, output: finishedOutput, paginate: paginate, paginatedOutput: finishedPaginatedOutput, fileIO: fileIO) {
          return PartitionedRenderingContext(key: key, items: $0, allItems: $1, siteMetadata: $2, paginator: $3)
        }
      }
    }
  }

  /// A convenience version of partitionedWriter that splits Items based on year.
  static func yearWriter(_ renderer: @escaping (PartitionedRenderingContext<Int, M, SiteMetadata>) throws -> String, output: Path = "[key]/index.html", paginate: Int? = nil, paginatedOutput: Path = "[key]/page/[page]/index.html") -> Self {
    let partitioner: ([Item<M>]) -> [Int: [Item<M>]] = { items in
      var itemsPerYear = [Int: [Item<M>]]()

      for item in items {
        let year = item.date.year
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

  /// A convenience version of partitionedWriter that splits Items based on tags.
  /// (Tags can be any `[String]` array.)
  static func tagWriter(_ renderer: @escaping (PartitionedRenderingContext<String, M, SiteMetadata>) throws -> String, output: Path = "tag/[key]/index.html", paginate: Int? = nil, paginatedOutput: Path = "tag/[key]/page/[page]/index.html", tags: @escaping (Item<M>) -> [String]) -> Self {
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
  static func writePages<Context>(renderer: @escaping (Context) throws -> String, items: [Item<M>], allItems: [AnyItem], siteMetadata: SiteMetadata, outputRoot: Path, outputPrefix: Path, output: Path, paginate: Int?, paginatedOutput: Path, fileIO: FileIO, getContext: ([Item<M>], [AnyItem], SiteMetadata, Paginator?) -> Context) throws {
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

        let context = getContext(firstItems, allItems, siteMetadata, paginator)
        let node = try renderer(context)
        try fileIO.write(outputRoot + outputPrefix + output, node)
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

        let finishedOutput = Path(paginatedOutput.string.replacingOccurrences(of: "[page]", with: "\(currentPage)"))
        let context = getContext(items, allItems, siteMetadata, paginator)
        let node = try renderer(context)
        try fileIO.write(outputRoot + outputPrefix + finishedOutput, node)
      }
    } else {
      let context = getContext(items, allItems, siteMetadata, nil)
      let node = try renderer(context)
      try fileIO.write(outputRoot + outputPrefix + output, node)
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
