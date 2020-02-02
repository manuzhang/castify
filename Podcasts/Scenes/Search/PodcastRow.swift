//
//  PodcastRow.swift
//  Search
//
//  Created by Alberto on 08/06/2019.
//  Copyright © 2019 com.github.albertopeam. All rights reserved.
//

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
        .clipShape(Circle())
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