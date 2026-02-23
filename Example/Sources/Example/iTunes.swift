import Foundation
import PathKit
import Saga

struct ITunesResponse: Decodable {
  let results: [ITunesResult]
}

struct ITunesResult: Decodable {
  let trackCensoredName: String
  let artworkUrl100: String
  let previewUrl: String
  let trackViewUrl: String
  let artistName: String
  let releaseDate: String
}

func fetchBeatlesVideos() async throws -> [Item<MusicVideoMetadata>] {
  let url = URL(string: "https://itunes.apple.com/search?term=the+beatles&media=musicVideo&limit=4")!
  let (data, _) = try await URLSession.shared.data(from: url)
  let response = try JSONDecoder().decode(ITunesResponse.self, from: data)

  let dateFormatter = ISO8601DateFormatter()

  return response.results.map { result in
    let date = dateFormatter.date(from: result.releaseDate) ?? Date()
    let slug = result.trackCensoredName.slugified
    return Item(
      title: result.trackCensoredName,
      date: date,
      relativeDestination: Path("videos/\(slug)/index.html"),
      metadata: MusicVideoMetadata(
        artworkUrl: result.artworkUrl100,
        previewUrl: result.previewUrl,
        trackViewUrl: result.trackViewUrl,
        artistName: result.artistName
      )
    )
  }
}
