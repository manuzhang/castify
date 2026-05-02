import Foundation

class Episode: Codable, Equatable, Hashable {

  let title: String
  let pubDate: Date
  let description: String
  let author: String
  let streamUrl: String
  let audio: URL?
  let duration: TimeInterval?

  var fileUrl: String?
  var imageUrl: String?

  private var played: Bool = false
  private var deleted: Bool = false
  private var progress: Float = 0.0
  private var starred: Bool = false

  init(title: String,
       pubDate: Date = Date(),
       description: String = "",
       author: String = "",
       streamUrl: String = "",
       imageUrl: String? = nil,
       duration: TimeInterval? = nil,
       fileUrl: String? = nil) {
    self.title = title
    self.pubDate = pubDate
    self.description = description
    self.author = author
    self.streamUrl = streamUrl
    self.audio = URL(string: streamUrl)
    self.imageUrl = imageUrl
    self.duration = duration
    self.fileUrl = fileUrl
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(title)
    hasher.combine(author)
    hasher.combine(streamUrl)
  }

  func setProgress(progress: Float) {
    self.progress = progress
    if (!played && progress > 0) {
      played = true
    }
  }

  func imageURL() -> URL? {
    guard let imageUrl = imageUrl else {
      return nil
    }

    return URL(string: imageUrl)
  }

  var cleanDescription: String {
    description.strippingHTML
  }

  static func ==(lhs: Episode, rhs: Episode) -> Bool {
    if lhs.title != rhs.title {
      return false
    }
    if lhs.author != rhs.author {
      return false
    }
    if lhs.streamUrl != rhs.streamUrl {
      return false
    }
    return true
  }
}
