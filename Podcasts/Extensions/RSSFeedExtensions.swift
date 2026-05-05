import Foundation

struct ParsedPodcastFeed {
  let description: String
  let imageUrl: String?
  let episodes: [Episode]
}

enum PodcastFeedParserError: LocalizedError {
  case invalidFeed

  var errorDescription: String? {
    switch self {
    case .invalidFeed:
      return LocalizationService.shared.text(.podcastFeedUnavailable)
    }
  }
}

final class PodcastFeedParser: NSObject {

  private struct EpisodeDraft {
    var title = ""
    var pubDate = Date()
    var description = ""
    var subtitle = ""
    var author = ""
    var streamUrl = ""
    var imageUrl: String?
    var duration: TimeInterval?

    func episode(fallbackImageUrl: String?) -> Episode? {
      guard !title.isEmpty || !streamUrl.isEmpty else {
        return nil
      }

      let episodeDescription = subtitle.isEmpty ? description : subtitle
      return Episode(
        title: title.isEmpty ? LocalizationService.shared.text(.untitledEpisode) : title,
        pubDate: pubDate,
        description: episodeDescription,
        author: author,
        streamUrl: streamUrl,
        imageUrl: imageUrl ?? fallbackImageUrl,
        duration: duration
      )
    }
  }

  private var feedDescription = ""
  private var feedImageUrl: String?
  private var episodeDrafts = [Episode]()
  private var currentEpisode: EpisodeDraft?
  private var elementStack = [String]()
  private var textStack = [String]()

  func parse(data: Data) throws -> ParsedPodcastFeed {
    feedDescription = ""
    feedImageUrl = nil
    episodeDrafts = []
    currentEpisode = nil
    elementStack = []
    textStack = []

    let parser = XMLParser(data: data)
    parser.delegate = self

    if parser.parse() {
      return ParsedPodcastFeed(
        description: feedDescription.strippingHTML,
        imageUrl: feedImageUrl,
        episodes: episodeDrafts
      )
    }

    throw parser.parserError ?? PodcastFeedParserError.invalidFeed
  }

  private var isInsideItem: Bool {
    currentEpisode != nil
  }

  private func normalized(_ elementName: String) -> String {
    elementName.lowercased()
  }

  private func trimmed(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func date(from value: String) -> Date {
    let formats = [
      "E, d MMM yyyy HH:mm:ss Z",
      "E, dd MMM yyyy HH:mm:ss Z",
      "d MMM yyyy HH:mm:ss Z",
      "dd MMM yyyy HH:mm:ss Z",
      "yyyy-MM-dd'T'HH:mm:ssZ",
      "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
    ]

    for format in formats {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = format
      if let date = formatter.date(from: value) {
        return date
      }
    }

    return ISO8601DateFormatter().date(from: value) ?? Date()
  }

  private func duration(from value: String) -> TimeInterval? {
    let cleanedValue = trimmed(value)
    if let seconds = TimeInterval(cleanedValue) {
      return seconds
    }

    let parts = cleanedValue
      .split(separator: ":")
      .compactMap { TimeInterval($0) }

    switch parts.count {
    case 2:
      return parts[0] * 60 + parts[1]
    case 3:
      return parts[0] * 3600 + parts[1] * 60 + parts[2]
    default:
      return nil
    }
  }
}

extension PodcastFeedParser: XMLParserDelegate {

  func parser(_ parser: XMLParser,
              didStartElement elementName: String,
              namespaceURI: String?,
              qualifiedName qName: String?,
              attributes attributeDict: [String: String] = [:]) {
    let element = normalized(elementName)
    elementStack.append(element)
    textStack.append("")

    if element == "item" {
      currentEpisode = EpisodeDraft()
      return
    }

    if element == "enclosure", isInsideItem {
      currentEpisode?.streamUrl = attributeDict["url"] ?? ""
    }

    if element == "itunes:image" {
      let imageUrl = attributeDict["href"]
      if isInsideItem {
        currentEpisode?.imageUrl = imageUrl
      } else {
        feedImageUrl = imageUrl
      }
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    guard !textStack.isEmpty else {
      return
    }

    textStack[textStack.count - 1] += string
  }

  func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
    guard let string = String(data: CDATABlock, encoding: .utf8) else {
      return
    }
    guard !textStack.isEmpty else {
      return
    }

    textStack[textStack.count - 1] += string
  }

  func parser(_ parser: XMLParser,
              didEndElement elementName: String,
              namespaceURI: String?,
              qualifiedName qName: String?) {
    let element = normalized(elementName)
    let rawText = textStack.popLast() ?? ""
    let text = trimmed(rawText)

    if var episode = currentEpisode {
      switch element {
      case "title":
        episode.title = text
      case "description", "content:encoded":
        if !text.isEmpty {
          episode.description = text
        }
      case "itunes:subtitle":
        episode.subtitle = text
      case "itunes:author", "author":
        if !text.isEmpty {
          episode.author = text
        }
      case "pubdate":
        episode.pubDate = date(from: text)
      case "itunes:duration":
        episode.duration = duration(from: text)
      default:
        break
      }
      currentEpisode = episode
    } else {
      switch element {
      case "description":
        if feedDescription.isEmpty {
          feedDescription = text
        }
      case "url":
        if elementStack.contains("image"), feedImageUrl == nil {
          feedImageUrl = text
        }
      default:
        break
      }
    }

    if element == "item" {
      if let episode = currentEpisode?.episode(fallbackImageUrl: feedImageUrl) {
        episodeDrafts.append(episode)
      }
      currentEpisode = nil
    }

    if !elementStack.isEmpty {
      elementStack.removeLast()
    }

    if !textStack.isEmpty {
      textStack[textStack.count - 1] += rawText
    }
  }
}
