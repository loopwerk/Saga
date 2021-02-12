import PathKit
import Foundation

public struct PageRenderingContext<M: Metadata, SiteMetadata: Metadata> {
  public let page: Page<M>
  public let pages: [Page<M>]
  public let allPages: [AnyPage]
  public let siteMetadata: SiteMetadata
}

public struct PagesRenderingContext<M: Metadata, SiteMetadata: Metadata> {
  public let pages: [Page<M>]
  public let allPages: [AnyPage]
  public let siteMetadata: SiteMetadata
}

public struct PartitionedRenderingContext<T, M: Metadata, SiteMetadata: Metadata> {
  public let key: T
  public let pages: [Page<M>]
  public let allPages: [AnyPage]
  public let siteMetadata: SiteMetadata
}

public struct Writer<M: Metadata, SiteMetadata: Metadata> {
  let run: ([Page<M>], [AnyPage], SiteMetadata, Path, Path) throws -> Void
}

public extension Writer {
  /// Write a single Page to disk, using Page.destination as the destination path
  static func pageWriter(_ renderer: @escaping (PageRenderingContext<M, SiteMetadata>) -> String) -> Self {
    Writer { pages, allPages, siteMetadata, outputRoot, outputPrefix in
      for page in pages {
        let context = PageRenderingContext(page: page, pages: pages, allPages: allPages, siteMetadata: siteMetadata)
        let node = renderer(context)
        try Writer.write(to: outputRoot + page.relativeDestination, content: node)
      }
    }
  }

  /// Writes an array of Pages into a single output file.
  /// As such, it needs an output path, for example "articles/index.html".
  static func listWriter(_ renderer: @escaping (PagesRenderingContext<M, SiteMetadata>) -> String, output: Path = "index.html") -> Self {
    return Self { pages, allPages, siteMetadata, outputRoot, outputPrefix in
      let context = PagesRenderingContext(pages: pages, allPages: allPages, siteMetadata: siteMetadata)
      let node = renderer(context)
      try Writer.write(to: outputRoot + outputPrefix + output, content: node)
    }
  }

  /// Writes an array of pages into multiple output files.
  /// Use this to partition an array of pages into a dictionary of pages, with a custom key.
  /// The output path is a template where [key] will be replaced with the key uses for the partition.
  /// Example: "articles/[key]/index.html"
  static func partitionedWriter<T>(_ renderer: @escaping (PartitionedRenderingContext<T, M, SiteMetadata>) -> String, output: Path = "[key]/index.html", partitioner: @escaping ([Page<M>]) -> [T: [Page<M>]]) -> Self {
    return Self { pages, allPages, siteMetadata, outputRoot, outputPrefix in
      let partitions = partitioner(pages)

      for (key, pagesInPartition) in partitions {
        let finishedOutput = output.string.replacingOccurrences(of: "[key]", with: "\(key)")
        let context = PartitionedRenderingContext(key: key, pages: pagesInPartition, allPages: allPages, siteMetadata: siteMetadata)
        let node = renderer(context)
        try Writer.write(to: outputRoot + outputPrefix + finishedOutput, content: node)
      }
    }
  }

  /// A convenience version of partitionedWriter that splits pages based on year
  static func yearWriter(_ renderer: @escaping (PartitionedRenderingContext<Int, M, SiteMetadata>) -> String, output: Path = "[key]/index.html") -> Self {
    let partitioner: ([Page<M>]) -> [Int: [Page<M>]] = { pages in
      var pagesPerYear = [Int: [Page<M>]]()

      for page in pages {
        let year = page.date.year
        if var pagesArray = pagesPerYear[year] {
          pagesArray.append(page)
          pagesPerYear[year] = pagesArray
        } else {
          pagesPerYear[year] = [page]
        }
      }

      return pagesPerYear
    }

    return Self.partitionedWriter(renderer, output: output, partitioner: partitioner)
  }

  /// A convenience version of partitionedWriter that splits pages based on tags
  /// (tags can be any [String] array)
  static func tagWriter(_ renderer: @escaping (PartitionedRenderingContext<String, M, SiteMetadata>) -> String, output: Path = "tag/[key]/index.html", tags: @escaping (Page<M>) -> [String]) -> Self {
    let partitioner: ([Page<M>]) -> [String: [Page<M>]] = { pages in
      var pagesPerTag = [String: [Page<M>]]()

      for page in pages {
        for tag in tags(page) {
          if var pagesArray = pagesPerTag[tag] {
            pagesArray.append(page)
            pagesPerTag[tag] = pagesArray
          } else {
            pagesPerTag[tag] = [page]
          }
        }
      }

      return pagesPerTag
    }

    return Self.partitionedWriter(renderer, output: output, partitioner: partitioner)
  }
}

private extension Writer {
  static func write(to destination: Path, content: String) throws {
    try destination.parent().mkpath()
    try destination.write(content)
  }
}

private extension Date {
  var year: Int {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy"
    return Int(formatter.string(from: self))!
  }
}
