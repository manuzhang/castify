import Foundation
import SwiftUI

struct PodcastRow: View {

  let podcast: Podcast

  init(podcast: Podcast) {
    self.podcast = podcast
  }

  var body: some View {
    HStack(spacing: 12) {
      RemoteImage(url: self.podcast.thumbnail())
        .frame(width: 64, height: 64, alignment: .center)
        .background(Color(.tertiarySystemFill))
        .cornerRadius(8)
        .clipped()
      VStack(alignment: .leading, spacing: 4) {
        Text(podcast.trackName)
          .lineLimit(2)
          .font(.headline)
        Text(podcast.artistName)
          .lineLimit(1)
          .font(.subheadline)
          .foregroundColor(.secondary)
      }
    }
    .padding(.vertical, 4)
  }
}
