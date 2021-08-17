import Foundation

private let allowedCharacters = CharacterSet(charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_")

public extension CustomStringConvertible {
  var slugified: String {
    return self.description
      .components(separatedBy: allowedCharacters.inverted)
      .filter { $0 != "" }
      .joined(separator: "-")
      .lowercased()
  }
}
