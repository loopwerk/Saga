/*
 * Code borrowed from https://github.com/bryceac/AtomFeed
 * Author: Bryce campbell
 * License: MIT License
 */

import Foundation

/// A rendered which creates an Atom feed for Items
///
/// - Parameters:
///   - title: The title of the feed, usually your site title. Example: Loopwerk.io.
///   - author: The author of the articles.
///   - baseURL: The base URL of your website, for example https://www.loopwerk.io.
///   - summary: An optional function which takes an `Item` and returns its summary.
/// - Returns: A function which takes a rendering context, and returns a string.
public func atomFeed<Context: AtomContext, M>(title: String, author: String? = nil, baseURL: URL, summary: ((Item<M>) -> String?)? = nil) -> (_ context: Context) -> String where Context.M == M {
  let RFC3339_DF = ISO8601DateFormatter()
  
  return { context in
    let feedPath = context.outputPath.string
    
    // Create the root element
    let rootElement = XMLElement(name: "feed")
    rootElement.setAttributesWith(["xmlns": "http://www.w3.org/2005/Atom"])
    
    // Create the XML document
    let XML = XMLDocument(rootElement: rootElement)
    
    let idElement = XMLElement(name: "id")
    idElement.stringValue = baseURL.appendingPathComponent(feedPath).absoluteString
    rootElement.addChild(idElement)
    
    rootElement.addChild(XMLElement(name: "title", stringValue: title))
    
    if let author = author {
      let authorElement = XMLElement(name: "author")
      authorElement.addChild(XMLElement(name: "name", stringValue: author))
      rootElement.addChild(authorElement)
    }
    
    let linkElement = XMLElement(name: "link")
    linkElement.setAttributesWith(["rel": "self", "href": baseURL.absoluteString])
    rootElement.addChild(linkElement)
    
    let updatedElement = XMLElement(name: "updated", stringValue: RFC3339_DF.string(from: Date()))
    rootElement.addChild(updatedElement)
    
    // add entries to feed
    for item in context.items {
      // create entry element
      let entryElement = XMLElement(name: "entry")
      
      let idElement = XMLElement(name: "id")
      idElement.stringValue = baseURL.appendingPathComponent(item.url).absoluteString

      entryElement.addChild(idElement)
      entryElement.addChild(XMLElement(name: "title", stringValue: item.title))
      entryElement.addChild(XMLElement(name: "updated", stringValue: RFC3339_DF.string(from: item.lastModified)))
      
      if let summary, let summaryString = summary(item) {
        let summaryElement = XMLElement(name: "summary", stringValue: summaryString)
        let alternateElement = XMLElement(name: "link")
        alternateElement.setAttributesWith(["rel": "alternate", "href": baseURL.appendingPathComponent(item.url).absoluteString])
        entryElement.addChild(summaryElement)
        entryElement.addChild(alternateElement)
      } else {
        let contentElement = XMLElement(name: "content", stringValue: item.body)
        contentElement.setAttributesWith(["type": "html"])
        entryElement.addChild(contentElement)
      }
      
      rootElement.addChild(entryElement)
    }
    
    return String(data: XML.xmlData(options: [.nodePrettyPrint]), encoding: .utf8) ?? ""
  }
}
