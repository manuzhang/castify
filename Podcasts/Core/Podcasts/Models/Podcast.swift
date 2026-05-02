import Foundation


struct Podcast: Codable, Hashable {
  let trackId: Int
  let trackName: String
  let trackCount: Int
  let artistName: String
  let artworkUrl100: String
  let artworkUrl600: String?
  let feedUrl: String

  enum CodingKeys: String, CodingKey {
    case trackId
    case trackName
    case trackCount
    case artistName
    case artworkUrl100
    case artworkUrl600
    case feedUrl
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    trackId = try container.decodeIfPresent(Int.self, forKey: .trackId) ?? 0
    trackName = try container.decodeIfPresent(String.self, forKey: .trackName) ?? "Untitled Podcast"
    trackCount = try container.decodeIfPresent(Int.self, forKey: .trackCount) ?? 0
    artistName = try container.decodeIfPresent(String.self, forKey: .artistName) ?? ""
    artworkUrl100 = try container.decodeIfPresent(String.self, forKey: .artworkUrl100) ?? ""
    artworkUrl600 = try container.decodeIfPresent(String.self, forKey: .artworkUrl600)
    feedUrl = try container.decodeIfPresent(String.self, forKey: .feedUrl) ?? ""
  }

  init(trackId: Int,
       trackName: String,
       trackCount: Int,
       artistName: String,
       artworkUrl100: String,
       artworkUrl600: String? = nil,
       feedUrl: String) {
    self.trackId = trackId
    self.trackName = trackName
    self.trackCount = trackCount
    self.artistName = artistName
    self.artworkUrl100 = artworkUrl100
    self.artworkUrl600 = artworkUrl600
    self.feedUrl = feedUrl
  }

  func thumbnail() -> URL? {
    artworkURL(preferLargeArtwork: false)
  }

  func artworkURL(preferLargeArtwork: Bool = true) -> URL? {
    if preferLargeArtwork, let artworkUrl600 = artworkUrl600, let url = URL(string: artworkUrl600) {
      return url
    }

    return URL(string: artworkUrl100)
  }
}
