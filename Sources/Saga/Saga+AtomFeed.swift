/*
 * Code borrowed from https://github.com/bryceac/AtomFeed
 * Author: Bryce campbell
 * License: MIT License
 */

import Foundation
import SagaPathKit

#if canImport(FoundationXML)
  import FoundationXML
#endif

public extension Saga {
  /// A renderer which creates an Atom feed for Items.
  @available(*, deprecated, message: "Use atomFeed(title:author:baseURL:itemTitle:summary:image:date:) instead, which takes a closure (or a keypath like \\.date)")
  @_documentation(visibility: private)
  @preconcurrency
  static func atomFeed<Context: AtomContext>(title: String, author: String? = nil, baseURL: URL, itemTitle: (@Sendable (Item<Context.M>) -> String)? = nil, summary: (@Sendable (Item<Context.M>) -> String?)? = nil, image: (@Sendable (Item<Context.M>) -> String?)? = nil, dateKeyPath: KeyPath<Item<Context.M>, Date>) -> (@Sendable (_ context: Context) -> String) {
    nonisolated(unsafe) let dateKeyPath = dateKeyPath
    return atomFeed(title: title, author: author, baseURL: baseURL, itemTitle: itemTitle, summary: summary, image: image, date: { $0[keyPath: dateKeyPath] })
  }

  /// A renderer which creates an Atom feed for Items.
  ///
  /// For JSON Feed and other formats, see <doc:CustomFeedFormats>.
  ///
  /// - Parameters:
  ///   - title: The title of the feed, usually your site title. Example: Loopwerk.io.
  ///   - author: The author of the articles.
  ///   - baseURL: The base URL of your website, for example https://www.loopwerk.io.
  ///   - itemTitle: An optional function which takes an `Item` and returns the title to use for its entry. Defaults to the item's `title`. Useful when feed titles should differ from the parsed title, for example when applying an SEO title policy or stripping Markdown emphasis markers.
  ///   - summary: An optional function which takes an `Item` and returns its summary.
  ///   - image: An optional function which takes an `Item` and returns its image URL (absolute or relative to baseURL).
  ///   - date: A function which takes an `Item` and returns the date to use for the <updated> field. Defaults to `lastModified`. A keypath like `\.date` works too.
  /// - Returns: A function which takes a rendering context, and returns a string.
  @preconcurrency
  static func atomFeed<Context: AtomContext>(title: String, author: String? = nil, baseURL: URL, itemTitle: (@Sendable (Item<Context.M>) -> String)? = nil, summary: (@Sendable (Item<Context.M>) -> String?)? = nil, image: (@Sendable (Item<Context.M>) -> String?)? = nil, date: @escaping @Sendable (Item<Context.M>) -> Date = { $0.lastModified }) -> (@Sendable (_ context: Context) -> String) {
    // The feed only gets this context's items, which are all Item<Context.M>, so these casts can't fail
    return { context in
      atomFeedXML(
        title: title, author: author, baseURL: baseURL, outputPath: context.outputPath, items: context.items,
        itemTitle: { itemTitle?($0 as! Item<Context.M>) },
        summary: { summary?($0 as! Item<Context.M>) },
        image: { image?($0 as! Item<Context.M>) },
        date: { date($0 as! Item<Context.M>) }
      )
    }
  }

  /// A renderer which creates an Atom feed from items of different types, for example articles and photos in one feed.
  ///
  /// Use it with ``StepBuilder/createPage(_:using:)``. The closures receive an `AnyItem`; cast it to read typed metadata.
  ///
  /// ```swift
  /// .createPage("feed.xml", using: Saga.atomFeed(
  ///   title: "Example",
  ///   baseURL: URL(string: "https://www.example.com")!,
  ///   filter: { $0 is Item<ArticleMetadata> || $0 is Item<PhotoMetadata> },
  ///   summary: { ($0 as? Item<ArticleMetadata>)?.metadata.summary }
  /// ))
  /// ```
  ///
  /// - Parameters:
  ///   - title: The title of the feed, usually your site title. Example: Loopwerk.io.
  ///   - author: The author of the articles.
  ///   - baseURL: The base URL of your website, for example https://www.loopwerk.io.
  ///   - filter: A function which decides which of all items are included in the feed.
  ///   - sorting: An optional comparison function used to sort the included items. Defaults to newest first by `date`.
  ///   - itemTitle: An optional function which takes an item and returns the title to use for its entry. Defaults to the item's `title`.
  ///   - summary: An optional function which takes an item and returns its summary.
  ///   - image: An optional function which takes an item and returns its image URL (absolute or relative to baseURL).
  ///   - date: A function which takes an item and returns the date to use for the <updated> field. Defaults to `lastModified`. A keypath like `\.date` works too.
  /// - Returns: A function which takes a page rendering context, and returns a string.
  @preconcurrency
  static func atomFeed(title: String, author: String? = nil, baseURL: URL, filter: @escaping @Sendable (AnyItem) -> Bool, sorting: (@Sendable (AnyItem, AnyItem) -> Bool)? = nil, itemTitle: (@Sendable (AnyItem) -> String)? = nil, summary: (@Sendable (AnyItem) -> String?)? = nil, image: (@Sendable (AnyItem) -> String?)? = nil, date: @escaping @Sendable (AnyItem) -> Date = { $0.lastModified }) -> (@Sendable (_ context: PageRenderingContext) -> String) {
    let sorting = sorting ?? { date($0) > date($1) }

    return { context in
      atomFeedXML(title: title, author: author, baseURL: baseURL, outputPath: context.outputPath, items: context.allItems.filter(filter).sorted(by: sorting), itemTitle: { itemTitle?($0) }, summary: { summary?($0) }, image: { image?($0) }, date: date)
    }
  }
}

private func atomFeedXML(title: String, author: String?, baseURL: URL, outputPath: Path, items: [AnyItem], itemTitle: (AnyItem) -> String?, summary: (AnyItem) -> String?, image: (AnyItem) -> String?, date: (AnyItem) -> Date) -> String {
  let RFC3339_DF = ISO8601DateFormatter()
  // Create the root element
  let rootElement = XMLElement(name: "feed")
  rootElement.setAttributesWith([
    "xmlns": "http://www.w3.org/2005/Atom",
    "xmlns:media": "http://search.yahoo.com/mrss/",
  ])

  // Create the XML document
  let XML = XMLDocument(rootElement: rootElement)

  let idElement = XMLElement(name: "id")
  idElement.stringValue = baseURL.appendingPathComponent(outputPath.string).absoluteString
  rootElement.addChild(idElement)

  rootElement.addChild(XMLElement(name: "title", stringValue: title))

  if let author {
    let authorElement = XMLElement(name: "author")
    authorElement.addChild(XMLElement(name: "name", stringValue: author))
    rootElement.addChild(authorElement)
  }

  let linkElement = XMLElement(name: "link")
  linkElement.setAttributesWith(["rel": "self", "href": baseURL.appendingPathComponent(outputPath.string).absoluteString])
  rootElement.addChild(linkElement)

  let updatedElement = XMLElement(name: "updated", stringValue: RFC3339_DF.string(from: Date()))
  rootElement.addChild(updatedElement)

  // add entries to feed
  for item in items {
    // create entry element
    let entryElement = XMLElement(name: "entry")

    let idElement = XMLElement(name: "id")
    idElement.stringValue = baseURL.appendingPathComponent(item.url).absoluteString

    entryElement.addChild(idElement)
    entryElement.addChild(XMLElement(name: "title", stringValue: itemTitle(item) ?? item.title))
    entryElement.addChild(XMLElement(name: "updated", stringValue: RFC3339_DF.string(from: date(item))))

    if let summaryString = summary(item) {
      let summaryElement = XMLElement(name: "summary", stringValue: summaryString)
      entryElement.addChild(summaryElement)
    }

    let contentElement = XMLElement(name: "content", stringValue: item.body)
    contentElement.setAttributesWith(["type": "html"])
    entryElement.addChild(contentElement)

    let alternateElement = XMLElement(name: "link")
    alternateElement.setAttributesWith(["rel": "alternate", "href": baseURL.appendingPathComponent(item.url).absoluteString])
    entryElement.addChild(alternateElement)

    if let imagePath = image(item) {
      let absoluteImageURL = imagePath.hasPrefix("http://") || imagePath.hasPrefix("https://")
        ? imagePath
        : baseURL.appendingPathComponent(imagePath).absoluteString
      let imageElement = XMLElement(name: "media:content")
      imageElement.setAttributesWith(["url": absoluteImageURL, "medium": "image"])
      entryElement.addChild(imageElement)
    }

    rootElement.addChild(entryElement)
  }

  return String(data: XML.xmlData(options: [.nodePrettyPrint]), encoding: .utf8) ?? ""
}
