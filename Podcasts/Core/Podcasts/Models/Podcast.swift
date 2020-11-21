//
//  Podcast.swift
//  Search
//
//  Created by Eugene Karambirov on 21/09/2018.
//  Copyright © 2018 Eugene Karambirov. All rights reserved.
//

import Foundation


struct Podcast: Codable, Hashable {
  let trackId: Int
  let trackName: String
  let trackCount: Int
  let artistName: String
  let artworkUrl100: String
  let feedUrl: String

  func thumbnail() -> URL? {
    URL(string: artworkUrl100)
  }
}
