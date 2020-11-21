import SwiftUI

struct EpisodeRow: View {

  let episode: Episode

  var body: some View {
    VStack(alignment: .leading) {
      Text(episode.title)
        .font(.body)
        .lineLimit(2)
      Text(episode.pubDate.formatMedium)
        .font(.caption)
    }
  }

}

