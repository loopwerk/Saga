import Foundation

private let allowedCharacters = CharacterSet(charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_")

public extension CustomStringConvertible {
  /// Returns a slugified version of the `String`: only letters, numbers, dash and underscore are allowed; everything else is replaced with a dash. The returned string is lowercased.
  var slugified: String {
    return self.description
      .replacingOccurrences(of: " - ", with: "-")
      .components(separatedBy: allowedCharacters.inverted)
      .filter { $0 != "" }
      .joined(separator: "-")
      .lowercased()
  }
}
