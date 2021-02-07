import PathKit
import Foundation

public struct Writer<M: Metadata, SiteMetadata: Metadata> {
  public var write: (
    _ pages: [Page<M>],
    _ allPages: [AnyPage],
    _ siteMetadata: SiteMetadata,
    _ render: (Path, [String : Any], Path) throws -> Void,
    _ outputPath: Path,
    _ outputPrefix: Path) throws -> Void

  /// Parameters
  /// pages: [Page<M>]
  /// allPages: [AnyPage]
  /// siteMetadata: SiteMetadata
  /// render: (Path, [String : Any], Path) throws -> Void
  /// outputPath: Path
  /// outputPrefix: Path
  public init(write: @escaping ([Page<M>], [AnyPage], SiteMetadata, (Path, [String : Any], Path) throws -> Void, Path, Path) throws -> Void) {
    self.write = write
  }
}

public extension Writer {
  // Write a single Page to disk, using Page.destination as the destination path
  static func pageWriter(template: Path, keepExactPath: Bool = false, filter: @escaping ((Page<M>) -> Bool) = { _ in true }) -> Self {
    return Self { pages, allPages, siteMetadata, render, outputRoot, outputPrefix in
      let pages = pages.filter(filter)

      for page in pages {
        let context = [
          "page": page,
          "pages": pages,
          "allPages": allPages,
          "site": siteMetadata,
        ] as [String : Any]

        // Call out to the render function
        var destination: Path
        if page.relativeDestination.string.isEmpty {
          destination = page.relativeSource.makeOutputPath(keepExactPath: keepExactPath)
        } else {
          destination = page.relativeDestination
        }

        try render(page.template ?? template, context, outputRoot + destination)
      }
    }
  }

  // Writes an array of Pages into a single output file.
  // As such, it needs an output path, for example "articles/index.html".
  static func listWriter(template: Path, output: Path = "index.html", filter: @escaping ((Page<M>) -> Bool) = { _ in true }) -> Self {
    return Self { pages, allPages, siteMetadata, render, outputRoot, outputPrefix in
      let pages = pages.filter(filter)

      let context = [
        "pages": pages,
        "allPages": allPages,
        "site": siteMetadata,
      ] as [String : Any]

      // Call out to the render function
      try render(template, context, outputRoot + outputPrefix + output)
    }
  }

  // Writes an array of pages into multiple output files.
  // The output path is a template where [year] will be replaced with the year of the Page.
  // Example: "articles/[year]/index.html"
  static func yearWriter(template: Path, output: Path = "[year]/index.html", filter: @escaping ((Page<M>) -> Bool) = { _ in true }) -> Self {
    return Self { pages, allPages, siteMetadata, render, outputRoot, outputPrefix in
      let pages = pages.filter(filter)

      // Find all the years and their pages
      var pagesPerYear = [Int: [AnyPage]]()

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
        let context = [
          "year": year,
          "pages": pagesInYear,
          "allPages": allPages,
          "site": siteMetadata,
        ] as [String : Any]

        // Call out to the render function
        let yearOutput = output.string.replacingOccurrences(of: "[year]", with: "\(year)")
        try render(template, context, outputRoot + outputPrefix + yearOutput)
      }
    }
  }

  // Writes an array of pages into multiple output files.
  // The output path is a template where [tag] will be replaced with the slugified tag.
  // Example: "articles/tag/[tag]/index.html"
  static func tagWriter(template: Path, output: Path = "tag/[tag]/index.html", tags: @escaping (Page<M>) -> [String], filter: @escaping ((Page<M>) -> Bool) = { _ in true }) -> Self {
    return Self { pages, allPages, siteMetadata, render, outputRoot, outputPrefix in
      let pages = pages.filter(filter)

      // Find all the tags and their pages
      var pagesPerTag = [String: [AnyPage]]()

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
        let context = [
          "tag": tag,
          "pages": pagesInTag,
          "allPages": allPages,
          "site": siteMetadata,
        ] as [String : Any]

        // Call out to the render function
        let yearOutput = output.string.replacingOccurrences(of: "[tag]", with: tag.slugify())
        try render(template, context, outputRoot + outputPrefix + yearOutput)
      }
    }
  }
}

private extension Date {
  var year: Int {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy"
    return Int(formatter.string(from: self))!
  }
}
