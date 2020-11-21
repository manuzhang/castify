import Foundation
import KingfisherSwiftUI
import SwiftUI

struct PodcastRow: View {

  let podcast: Podcast

  init(podcast: Podcast) {
    self.podcast = podcast
  }

  var body: some View {
    HStack {
      KFImage(self.podcast.thumbnail())
        .frame(width: 64, height: 64, alignment: .center)
        .aspectRatio(contentMode: ContentMode.fit)
        .clipShape(Rectangle())
      VStack(alignment: .leading) {
        Text(podcast.trackName)
          .lineLimit(nil)
          .font(.headline)
/*                Text(podcast.language)
                    .lineLimit(1)
                    .font(.caption)*/
      }
    }
  }
}