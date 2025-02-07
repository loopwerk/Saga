import PathKit

public struct ItemRenderingContext<M: Metadata> {
  public let item: Item<M>
  public let items: [Item<M>]
  public let allItems: [AnyItem]
  public let resources: [Path]
}

public struct ItemsRenderingContext<M: Metadata> {
  public let items: [Item<M>]
  public let allItems: [AnyItem]
  public let paginator: Paginator?
  public let outputPath: Path
}

public typealias ContextKey = CustomStringConvertible & Comparable
public struct PartitionedRenderingContext<T: ContextKey, M: Metadata> {
  public let key: T
  public let items: [Item<M>]
  public let allItems: [AnyItem]
  public let paginator: Paginator?
  public let outputPath: Path
}

/// A model representing a paginator.
///
/// When you use the `listWriter` or one of the `partitionedWriter` versions, you can choose to paginate the items into multiple output files.
/// The rendering context will be given a `Paginator` which can be used to include links to previous and next pages in your website.
///
/// This is very common for blogs, where the archive of all articles is paginated: 20 articles per page for example.
public struct Paginator {
  /// The current index.
  /// > Note: The first page has index 1.
  public let index: Int

  /// How many items are there per page.
  public let itemsPerPage: Int

  /// How many pages are there in total.
  public let numberOfPages: Int

  /// The `Path` to the previous page  in the `Paginator`.
  public let previous: Path?

  /// The `Path` to the next page in the `Paginator`.
  public let next: Path?
}
