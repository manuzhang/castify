import SwiftUI

struct PodcastHeaderView: View {

  let podcast: Podcast

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      RemoteImage(url: podcast.artworkURL())
        .frame(width: 128, height: 128)
        .background(Color(.tertiarySystemFill))
        .cornerRadius(8)
        .clipped()

      VStack(alignment: .leading, spacing: 8) {
        Text(podcast.trackName)
          .lineLimit(nil)
          .font(.headline)
        Text(podcast.artistName)
          .font(.subheadline)
          .foregroundColor(.secondary)
          .lineLimit(2)
        Text("\(podcast.trackCount) episodes")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .padding(.vertical, 8)
  }

}
