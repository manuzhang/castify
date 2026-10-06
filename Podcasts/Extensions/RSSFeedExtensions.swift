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
    var publicationDateIsKnown = false
    var guid: String?
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
        duration: duration,
        guid: guid,
        publicationDateIsKnown: publicationDateIsKnown
      )
    }
  }

  private var feedDescription = ""
  private var feedImageUrl: String?
  private var episodeDrafts = [Episode]()
  private var currentEpisode: EpisodeDraft?
  private var elementStack = [String]()
  private var textStack = [String]()
  private var channelCount = 0
  private var isRDFRoot = false

  func parse(data: Data) throws -> ParsedPodcastFeed {
    feedDescription = ""
    feedImageUrl = nil
    episodeDrafts = []
    currentEpisode = nil
    elementStack = []
    textStack = []
    channelCount = 0
    isRDFRoot = false

    let parser = XMLParser(data: data)
    parser.delegate = self
    parser.shouldProcessNamespaces = true

    // Well-formed error/HTML XML is not a successful RSS snapshot. An empty
    // RSS channel is valid, so do not require episodes to establish a baseline.
    if parser.parse(), channelCount == 1 {
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

  private func element(_ name: String, qualifiedName: String?, namespaceURI: String?) -> String {
    if namespaceURI == "http://www.w3.org/1999/02/22-rdf-syntax-ns#", normalized(name) == "rdf" {
      return "rdf:rdf"
    }
    if namespaceURI == "http://purl.org/rss/1.0/" { return normalized(name) }
    if namespaceURI == "http://purl.org/dc/elements/1.1/" { return "dc:" + normalized(name) }
    return normalized(qualifiedName ?? name)
  }

  private func trimmed(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func date(from value: String) -> Date? {
    var value = value
    // RFC 5322 section 4.3: 00...49 means 2000...2049, 50...99 means
    // 1950...1999. Expand before yyyy can accept a two-digit year literally.
    let pattern = "^(?:[A-Za-z]{3},\\s*)?\\d{1,2}\\s+[A-Za-z]{3}\\s+(\\d{2})(?=\\s+\\d{2}:)"
    if let expression = try? NSRegularExpression(pattern: pattern),
       let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
       let range = Range(match.range(at: 1), in: value), let year = Int(value[range]) {
      value.replaceSubrange(range, with: String(year + (year < 50 ? 2000 : 1900)))
    }
    // RFC zone abbreviations have fixed offsets, even when the publication
    // date falls in daylight-saving season. Avoid locale-dependent zone guesses.
    var zones = ["UT": "+0000", "GMT": "+0000", "EST": "-0500", "EDT": "-0400",
                 "CST": "-0600", "CDT": "-0500", "MST": "-0700", "MDT": "-0600",
                 "PST": "-0800", "PDT": "-0700"]
    // RSS references RFC 822 section 5.2: A...M are earlier than UT,
    // N...Y are later; J is unused. Keep that legacy interpretation explicit.
    for (index, letter) in "ABCDEFGHIKLM".enumerated() {
      zones[String(letter)] = String(format: "-%02d00", index + 1)
    }
    for (index, letter) in "NOPQRSTUVWXY".enumerated() {
      zones[String(letter)] = String(format: "+%02d00", index + 1)
    }
    zones["Z"] = "+0000"
    if let zone = value.split(whereSeparator: { $0.isWhitespace }).last,
       let offset = zones[String(zone).uppercased()],
       let range = value.range(of: String(zone), options: .backwards) {
      value.replaceSubrange(range, with: offset)
    }
    let formats = [
      "E, d MMM yyyy HH:mm:ss Z",
      "E, dd MMM yyyy HH:mm:ss Z",
      "d MMM yyyy HH:mm:ss Z",
      "dd MMM yyyy HH:mm:ss Z",
      "E, d MMM yyyy HH:mm Z",
      "E, dd MMM yyyy HH:mm Z",
      "d MMM yyyy HH:mm Z",
      "dd MMM yyyy HH:mm Z",
      "yyyy-MM-dd'T'HH:mm:ssZ",
      "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
      "yyyy-MM-dd'T'HH:mmZ",
      "yyyy-MM-dd"
    ]

    for format in formats {
      if format == "yyyy-MM-dd", value.count != 10 { continue }
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.dateFormat = format
      if let date = formatter.date(from: value) {
        return date
      }
    }

    return ISO8601DateFormatter().date(from: value)
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
    let element = element(elementName, qualifiedName: qName, namespaceURI: namespaceURI)
    if elementStack.isEmpty {
      isRDFRoot = namespaceURI == "http://www.w3.org/1999/02/22-rdf-syntax-ns#" && normalized(elementName) == "rdf"
    }
    elementStack.append(element)
    textStack.append("")

    let isRSS1Element = isRDFRoot && namespaceURI == "http://purl.org/rss/1.0/"
    if elementStack == ["rss", "channel"] || (isRSS1Element && elementStack == ["rdf:rdf", "channel"]) {
      channelCount += 1
    }

    if elementStack == ["rss", "channel", "item"] || (isRSS1Element && elementStack == ["rdf:rdf", "item"]) {
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
    let element = element(elementName, qualifiedName: qName, namespaceURI: namespaceURI)
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
      case "itunes:author", "author", "dc:creator":
        if !text.isEmpty && (element != "dc:creator" || namespaceURI == "http://purl.org/dc/elements/1.1/") {
          episode.author = text
        }
      case "guid":
        episode.guid = text
      case "pubdate", "dc:date":
        if (element == "pubdate" || namespaceURI == "http://purl.org/dc/elements/1.1/"),
           let parsedDate = date(from: text) {
          episode.pubDate = parsedDate
          episode.publicationDateIsKnown = true
        }
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
