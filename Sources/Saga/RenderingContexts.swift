import PathKit

/// The rendering context passed to an ``Writer/itemWriter(_:)`` renderer.
///
/// Contains the single item being rendered, along with all items from the same processing step,
/// all items across all steps, neighboring items for navigation, and any unhandled files (resources)
/// in the same folder as the item.
public struct ItemRenderingContext<M: Metadata> {
  /// The item being rendered.
  public let item: Item<M>

  /// All items from the same processing step, in sorted order.
  public let items: [Item<M>]

  /// All items across all registered processing steps.
  public let allItems: [AnyItem]

  /// Unhandled files in the same folder as the item, such as images or other static files.
  public let resources: [Path]

  /// The previous item in sorted order, or `nil` if this is the first item.
  public let previous: Item<M>?

  /// The next item in sorted order, or `nil` if this is the last item.
  public let next: Item<M>?
}

/// A protocol for rendering contexts that can be used to generate Atom feeds.
public protocol AtomContext {
  associatedtype M: Metadata

  /// The items to include in the feed.
  var items: [Item<M>] { get }

  /// The output path of the page being rendered.
  var outputPath: Path { get }
}

/// The rendering context passed to a ``Writer/listWriter(_:output:paginate:paginatedOutput:)`` renderer.
///
/// Contains all items from the processing step, optionally paginated.
public struct ItemsRenderingContext<M: Metadata>: AtomContext {
  /// All items from the same processing step (or the current page's slice when paginated), in sorted order.
  public let items: [Item<M>]

  /// All items across all registered processing steps.
  public let allItems: [AnyItem]

  /// Pagination information, or `nil` if the writer is not paginated.
  public let paginator: Paginator?

  /// The output path of the page being rendered.
  public let outputPath: Path
}

/// A type constraint for partition keys used in ``PartitionedRenderingContext``.
public typealias ContextKey = Comparable & CustomStringConvertible

/// The rendering context passed to a ``Writer/partitionedWriter(_:output:paginate:paginatedOutput:partitioner:)`` renderer,
/// as well as the convenience ``Writer/tagWriter(_:output:paginate:paginatedOutput:tags:)``
/// and ``Writer/yearWriter(_:output:paginate:paginatedOutput:)`` renderers.
///
/// Contains items grouped by a partition key (such as a tag or year), optionally paginated.
public struct PartitionedRenderingContext<T: ContextKey, M: Metadata>: AtomContext {
  /// The partition key for this group of items.
  public let key: T

  /// The items in this partition (or the current page's slice when paginated), in sorted order.
  public let items: [Item<M>]

  /// All items across all registered processing steps.
  public let allItems: [AnyItem]

  /// Pagination information, or `nil` if the writer is not paginated.
  public let paginator: Paginator?

  /// The output path of the page being rendered.
  public let outputPath: Path
}

/// The rendering context for template-driven pages created with ``Saga/createPage(_:using:)``.
///
/// Unlike other rendering contexts, this is not associated with any ``Item`` — it's for pages
/// that are purely template-driven, such as a homepage, search page, or 404 page.
public struct PageRenderingContext {
  /// All items across all registered processing steps.
  public let allItems: [AnyItem]

  /// The output path of the page being rendered.
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
