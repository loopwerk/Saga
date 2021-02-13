import Foundation
import PathKit

public struct Paginator {
  public let index: Int
  public let perPage: Int
  public let numberOfPages: Int
  public let previous: Path?
  public let next: Path?
}

public struct PaginatorConfig {
  let perPage: Int
  let output: Path

  public init(perPage: Int, output: Path = "page/[page]/index.html") {
    self.perPage = perPage
    self.output = output
  }
}
