import Foundation

struct OPMLFeed {
  let title: String
  let feedUrl: String
  let htmlUrl: String?
}

enum OPMLImportError: LocalizedError {
  case emptyFile
  case invalidFile
  case noFeedsFound

  var errorDescription: String? {
    switch self {
    case .emptyFile:
      return LocalizationService.shared.text(.selectedFileEmpty)
    case .invalidFile:
      return LocalizationService.shared.text(.invalidOPMLFile)
    case .noFeedsFound:
      return LocalizationService.shared.text(.noPodcastFeedsFound)
    }
  }
}

final class OPMLImportService: NSObject {

  private var feeds = [OPMLFeed]()
  private var seenFeedUrls = Set<String>()

  func parse(data: Data) throws -> [OPMLFeed] {
    guard !data.isEmpty else {
      throw OPMLImportError.emptyFile
    }

    feeds = []
    seenFeedUrls = []

    let parser = XMLParser(data: data)
    parser.delegate = self

    guard parser.parse() else {
      throw parser.parserError ?? OPMLImportError.invalidFile
    }

    guard !feeds.isEmpty else {
      throw OPMLImportError.noFeedsFound
    }

    return feeds
  }

  func podcasts(from feeds: [OPMLFeed]) -> [Podcast] {
    feeds.map { feed in
      Podcast(
        trackId: importedTrackId(for: feed.feedUrl),
        trackName: feed.title.isEmpty ? fallbackTitle(for: feed.feedUrl) : feed.title,
        trackCount: 0,
        artistName: "",
        artworkUrl100: "",
        artworkUrl600: nil,
        feedUrl: feed.feedUrl
      )
    }
  }

  private func appendFeed(from attributes: [String: String]) {
    guard let rawFeedUrl = attribute("xmlUrl", in: attributes) else {
      return
    }

    let feedUrl = rawFeedUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !feedUrl.isEmpty else {
      return
    }

    let normalizedFeedUrl = PodcastsService.normalizedFeedUrl(feedUrl)
    guard !seenFeedUrls.contains(normalizedFeedUrl) else {
      return
    }

    let title = nonEmptyAttribute("title", in: attributes)
      ?? nonEmptyAttribute("text", in: attributes)
      ?? fallbackTitle(for: feedUrl)
    let htmlUrl = nonEmptyAttribute("htmlUrl", in: attributes)
    feeds.append(OPMLFeed(title: title, feedUrl: feedUrl, htmlUrl: htmlUrl))
    seenFeedUrls.insert(normalizedFeedUrl)
  }

  private func attribute(_ name: String, in attributes: [String: String]) -> String? {
    attributes.first { $0.key.lowercased() == name.lowercased() }?.value
  }

  private func nonEmptyAttribute(_ name: String, in attributes: [String: String]) -> String? {
    guard let value = attribute(name, in: attributes)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
      return nil
    }

    return value.isEmpty ? nil : value
  }

  private func importedTrackId(for feedUrl: String) -> Int {
    let bytes = PodcastsService.normalizedFeedUrl(feedUrl).utf8
    let hash = bytes.reduce(UInt32(2166136261)) { result, byte in
      (result ^ UInt32(byte)) &* 16777619
    }
    let positive = Int(hash & 0x7fffffff)
    return -max(1, positive)
  }

  private func fallbackTitle(for feedUrl: String) -> String {
    guard let url = URL(string: feedUrl), let host = url.host, !host.isEmpty else {
      return LocalizationService.shared.text(.importedPodcast)
    }

    return host
  }
}

extension OPMLImportService: XMLParserDelegate {

  func parser(_ parser: XMLParser,
              didStartElement elementName: String,
              namespaceURI: String?,
              qualifiedName qName: String?,
              attributes attributeDict: [String: String] = [:]) {
    guard elementName.lowercased() == "outline" else {
      return
    }

    appendFeed(from: attributeDict)
  }
}
