import Foundation

public extension CustomStringConvertible {
  var slugified: String {
    return self.description.replacingOccurrences(of: " ", with: "-")
  }
}
