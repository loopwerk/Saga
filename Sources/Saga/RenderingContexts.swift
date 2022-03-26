public struct ItemRenderingContext<M: Metadata, SiteMetadata: Metadata> {
  public let item: Item<M>
  public let items: [Item<M>]
  public let allItems: [AnyItem]
  public let siteMetadata: SiteMetadata
}

public struct ItemsRenderingContext<M: Metadata, SiteMetadata: Metadata> {
  public let items: [Item<M>]
  public let allItems: [AnyItem]
  public let siteMetadata: SiteMetadata
  public let paginator: Paginator?
}

public typealias ContextKey = CustomStringConvertible & Comparable
public struct PartitionedRenderingContext<T: ContextKey, M: Metadata, SiteMetadata: Metadata> {
  public let key: T
  public let items: [Item<M>]
  public let allItems: [AnyItem]
  public let siteMetadata: SiteMetadata
  public let paginator: Paginator?
}
