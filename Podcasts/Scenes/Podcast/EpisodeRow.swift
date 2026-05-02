import SwiftUI

struct EpisodeRow: View {

  let episode: Episode

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "play.circle")
        .font(.system(size: 26))
        .foregroundColor(.blue)
        .frame(width: 32, height: 32)

      VStack(alignment: .leading, spacing: 5) {
      Text(episode.title)
        .font(.headline)
        .lineLimit(2)
      HStack(spacing: 6) {
        Text(episode.pubDate.formatMedium)
        if let duration = episode.duration, duration > 0 {
          Text("·")
          Text(duration.podcastDuration)
        }
      }
      .font(.caption)
      .foregroundColor(.secondary)
      }
    }
    .padding(.vertical, 6)
  }

}
