import Foundation

enum OPMLExportError: LocalizedError {
  case noSubscriptions

  var errorDescription: String? {
    switch self {
    case .noSubscriptions:
      return LocalizationService.shared.text(.noSubscribedPodcastsToSync)
    }
  }
}

final class OPMLExportService {

  func export(podcasts: [Podcast]) throws -> Data {
    let podcastsWithFeeds = podcasts.filter { !$0.feedUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    guard !podcastsWithFeeds.isEmpty else {
      throw OPMLExportError.noSubscriptions
    }

    var lines = [
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
      "<opml version=\"1.0\">",
      "  <head>",
      "    <title>Castify Subscribed Podcasts</title>",
      "  </head>",
      "  <body>",
      "    <outline text=\"feeds\" title=\"feeds\">"
    ]

    podcastsWithFeeds.forEach { podcast in
      let title = xmlEscaped(podcast.trackName.isEmpty ? LocalizationService.shared.text(.importedPodcast) : podcast.trackName)
      let feedUrl = xmlEscaped(podcast.feedUrl.trimmingCharacters(in: .whitespacesAndNewlines))
      lines.append("      <outline type=\"rss\" text=\"\(title)\" title=\"\(title)\" xmlUrl=\"\(feedUrl)\"/>")
    }

    lines.append(contentsOf: [
      "    </outline>",
      "  </body>",
      "</opml>",
      ""
    ])

    return Data(lines.joined(separator: "\n").utf8)
  }

  private func xmlEscaped(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&apos;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
  }
}
