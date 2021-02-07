import Foundation
import Stencil
import PathKit

// The default read function
internal extension Saga {
  func getEnvironment() -> Environment {
    let ext = Extension()

    ext.registerFilter("date") { (value: Any?, arguments: [Any?]) in
      guard let date = value as? Date else {
        return value
      }

      let formatter = DateFormatter()
      formatter.dateFormat = arguments.first as? String ?? "yyyy-MM-dd"
      return formatter.string(from: date)
    }

    ext.registerFilter("url") { (value: Any?) in
      return "type: \(String(describing: value))"
      guard let page = value as? AnyPage else {
        return "NOPE!"
      }
      var url = "/" + page.relativeDestination.string
      if url.hasSuffix("/index.html") {
        url.removeLast(10)
      }
      return url
    }

    ext.registerFilter("striptags") { (value: Any?) in
      guard let text = value as? String else {
        return value
      }
      return text.withoutHtmlTags
    }

    ext.registerFilter("wordcount") { (value: Any?) in
      guard let text = value as? String else {
        return value
      }
      return text.numberOfWords
    }

    ext.registerFilter("slugify") { (value: Any?) in
      guard let text = value as? String else {
        return value
      }
      return text.slugify()
    }

    ext.registerFilter("escape") { (value: Any?) in
      guard let text = value as? String else {
        return value
      }
      return text
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "&", with: "&amp;")
    }

    ext.registerFilter("truncate") { (value: Any?, arguments: [Any?]) in
      guard let text = value as? String else {
        return value
      }
      let length = arguments.first as? Int ?? 255
      return text.prefix(length)
    }

    let templatePath = rootPath + templates
    return Environment(loader: FileSystemLoader(paths: [templatePath]), extensions: [ext])
  }
}

private extension String {
  var numberOfWords: Int {
    let characterSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
    let components = self.components(separatedBy: characterSet)
    return components.filter { !$0.isEmpty }.count
  }

  // This is a sloppy implementation but sadly `NSAttributedString(data:options:documentAttributes:)`
  // is not available in CoreFoundation.
  var withoutHtmlTags: String {
    return self
      .replacingOccurrences(of: "(?m)<pre><span></span><code>[\\s\\S]+?</code></pre>", with: "", options: .regularExpression, range: nil)
      .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
  }
}
