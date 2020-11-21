import Foundation
import FeedKit

struct Episode: Codable, Equatable, Hashable {

  let title: String
  let pubDate: Date
  let description: String
  let author: String
  let streamUrl: String
  let audio: URL?

  var fileUrl: String?
  var imageUrl: String?

  init(feedItem: RSSFeedItem) {
    self.streamUrl = feedItem.enclosure?.attributes?.url ?? ""
    self.audio = URL(string: self.streamUrl)
    self.title = feedItem.title ?? ""
    self.pubDate = feedItem.pubDate ?? Date()
    self.description = feedItem.iTunes?.iTunesSubtitle ?? feedItem.description ?? ""
    self.author = feedItem.iTunes?.iTunesAuthor ?? ""
    self.imageUrl = feedItem.iTunes?.iTunesImage?.attributes?.href
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(title)
    hasher.combine(author)
  }

  static func ==(lhs: Episode, rhs: Episode) -> Bool {
    if lhs.title != rhs.title {
      return false
    }
    if lhs.author != rhs.author {
      return false
    }
    return true
  }
}
