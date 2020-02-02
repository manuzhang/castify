//
//  PodcastHeaderView.swift
//  Search
//
//  Created by Alberto on 10/06/2019.
//  Copyright © 2019 com.github.albertopeam. All rights reserved.
//

import KingfisherSwiftUI
import SwiftUI

struct PodcastHeaderView: View {

  let podcast: Podcast

  var body: some View {
    HStack {
      VStack {
        KFImage(podcast.thumbnail())
          .frame(width: 128, height: 128)
          .aspectRatio(contentMode: ContentMode.fit)
          .clipShape(Circle())
          .overlay(Circle().stroke(Color.white, lineWidth: 2))
          .shadow(radius: 4)

//        Text(podcast.language)
//          .frame(alignment: .trailing)
//          .lineLimit(1)
//          .font(.caption)
//          .foregroundColor(Color.red)
      }
      Spacer().frame(maxWidth: 20)
      VStack(alignment: .leading) {
        Text(podcast.trackName)
          .lineLimit(nil)
          .font(.headline)
        Spacer().frame(maxHeight: CGFloat(10))
//        Text(podcast.description)
//          .lineLimit(nil)
//          .font(.caption)
      }
    }.padding([.top])
  }

}

