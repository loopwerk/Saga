import PathKit
import Foundation

/// Run multiple item processors in sequence.
///
/// ```swift
/// .register(
///   metadata: EmptyMetadata.self,
///   readers: [.parsleyMarkdownReader],
///   itemProcessor: sequence(publicationDateInFilename, addExclamationPointToTitle)
///   writers: [.itemWriter(swim(renderPage))]
/// )
/// ```
public func sequence<M>(_ processors: ((Item<M>) async -> Void)...) -> (Item<M>) async -> Void {
  return { item in
    for processor in processors {
      await processor(item)
    }
  }
}

private let publicationDateFormatter: DateFormatter = {
  let pageProcessorDateFormatter = DateFormatter()
  pageProcessorDateFormatter.dateFormat = "yyyy-MM-dd"
  pageProcessorDateFormatter.timeZone = .current
  return pageProcessorDateFormatter
}()

/// An item processor that takes files such as "2021-01-27-post-with-date-in-filename"
/// and uses the date within the filename as the publication date.
public func publicationDateInFilename<M>(item: Item<M>) async {
  // If the filename starts with a valid date, use that as the Page's date and strip it from the destination path
  let first10 = String(item.relativeSource.lastComponentWithoutExtension.prefix(10))
  guard first10.count == 10, let date = publicationDateFormatter.date(from: first10) else {
    return
  }
  
  // Set the date
  item.published = date
  
  // And remove the first 11 characters from the filename
  let first11 = String(item.relativeSource.lastComponentWithoutExtension.prefix(11))
  item.relativeDestination = Path(
    item.relativeSource.string.replacingOccurrences(of: first11, with: "")
  ).makeOutputPath(itemWriteMode: .moveToSubfolder)
}
