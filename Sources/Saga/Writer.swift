import PathKit
import Foundation
import Slugify
import HTML
import Stencil

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

public struct TagRenderingContext<M: Metadata, SiteMetadata: Metadata> {
  public let tag: String
  public let pages: [Page<M>]
  public let allPages: [AnyPage]
  public let siteMetadata: SiteMetadata
}

public struct YearRenderingContext<M: Metadata, SiteMetadata: Metadata> {
  public let year: Int
  public let pages: [Page<M>]
  public let allPages: [AnyPage]
  public let siteMetadata: SiteMetadata
}

public struct Writer<M: Metadata, SiteMetadata: Metadata> {
  let run: ([Page<M>], [AnyPage], SiteMetadata, Path, Path) throws -> Void
}

public extension Writer {
  // Write a single Page to disk, using Page.destination as the destination path
  static func pageWriter(_ convert: @escaping (PageRenderingContext<M, SiteMetadata>) -> String) -> Self {
    Writer { pages, allPages, siteMetadata, outputRoot, outputPrefix in
      for page in pages {
        let context = PageRenderingContext(page: page, pages: pages, allPages: allPages, siteMetadata: siteMetadata)
        let node = convert(context)
        try Writer.write(to: outputRoot + page.relativeDestination, content: node)
      }
    }
  }

  // Writes an array of Pages into a single output file.
  // As such, it needs an output path, for example "articles/index.html".
  static func listWriter(_ convert: @escaping (PagesRenderingContext<M, SiteMetadata>) -> String, output: Path = "index.html") -> Self {
    return Self { pages, allPages, siteMetadata, outputRoot, outputPrefix in
      let context = PagesRenderingContext(pages: pages, allPages: allPages, siteMetadata: siteMetadata)
      let node = convert(context)
      try Writer.write(to: outputRoot + outputPrefix + output, content: node)
    }
  }

  // Writes an array of pages into multiple output files.
  // The output path is a template where [year] will be replaced with the year of the Page.
  // Example: "articles/[year]/index.html"
  static func yearWriter(_ convert: @escaping (YearRenderingContext<M, SiteMetadata>) -> String, output: Path = "[year]/index.html") -> Self {
    return Self { pages, allPages, siteMetadata, outputRoot, outputPrefix in
      // Find all the years and their pages
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

      for (year, pagesInYear) in pagesPerYear {
        let yearOutput = output.string.replacingOccurrences(of: "[year]", with: "\(year)")
        let context = YearRenderingContext(year: year, pages: pagesInYear, allPages: allPages, siteMetadata: siteMetadata)
        let node = convert(context)
        try Writer.write(to: outputRoot + outputPrefix + yearOutput, content: node)
      }
    }
  }

  // Writes an array of pages into multiple output files.
  // The output path is a template where [tag] will be replaced with the slugified tag.
  // Example: "articles/tag/[tag]/index.html"
  static func tagWriter(_ convert: @escaping (TagRenderingContext<M, SiteMetadata>) -> String, output: Path = "tag/[tag]/index.html", tags: @escaping (Page<M>) -> [String]) -> Self {
    return Self { pages, allPages, siteMetadata, outputRoot, outputPrefix in
      // Find all the tags and their pages
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

      for (tag, pagesInTag) in pagesPerTag {
        // Call out to the render function
        let tagOutput = output.string.replacingOccurrences(of: "[tag]", with: tag.slugify())
        let context = TagRenderingContext(tag: tag, pages: pagesInTag, allPages: allPages, siteMetadata: siteMetadata)
        let node = convert(context)
        try Writer.write(to: outputRoot + outputPrefix + tagOutput, content: node)
      }
    }
  }
}

public func swim<Context>(_ templateFunction: @escaping (Context) -> Node) -> ((Context) -> String) {
  return { context in
    let node = templateFunction(context)
    return node.toString()
  }
}

public extension Node {
  func toString() -> String {
    var result = ""
    self.write(to: &result)
    return result
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
