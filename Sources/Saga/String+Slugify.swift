import Foundation

public extension String {
  var slugified: String {
    return self.replacingOccurrences(of: " ", with: "-")
  }
}
