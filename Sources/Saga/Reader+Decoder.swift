import Foundation
import Codextended
import PathKit

public extension Reader {
  static func makeMetadataDecoder(for metadata: [String: String]) -> MetadataDecoder {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    dateFormatter.timeZone = .current

    return MetadataDecoder(
      metadata: metadata,
      dateFormatter: dateFormatter
    )
  }

  static func resolvePublishingDate(from path: Path, decoder: MetadataDecoder) throws -> Date {
    return try decoder.decodeIfPresent("date", as: Date.self) ?? path.creationDate ?? Date()
  }
}
