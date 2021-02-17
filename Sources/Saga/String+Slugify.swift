import Foundation

public extension CustomStringConvertible {
  var slugified: String {
    return self.description
      .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
      .joined(separator: "")
      .replacingOccurrences(of: " ", with: "-")
      .lowercased()
  }
}
