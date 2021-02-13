import Foundation
import PathKit

public struct Paginator {
  public let index: Int
  public let perPage: Int
  public let numberOfPages: Int
  public let previous: Path?
  public let next: Path?
}
