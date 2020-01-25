//
//  Episode.swift
//  Search
//
//  Created by Eugene Karambirov on 25/09/2018.
//  Copyright © 2018 Eugene Karambirov. All rights reserved.
//

import Foundation
import FeedKit

struct Episode: Codable, Equatable, Hashable {

  let title: String
  let pubDate: Date
  let description: String
  let author: String
  let streamUrl: String
  let audio: URL?

  var fileUrl: String?
  var imageUrl: String?

  init(feedItem: RSSFeedItem) {
    self.streamUrl = feedItem.enclosure?.attributes?.url ?? ""
    self.audio = URL(string: self.streamUrl)
    self.title = feedItem.title ?? ""
    self.pubDate = feedItem.pubDate ?? Date()
    self.description = feedItem.iTunes?.iTunesSubtitle ?? feedItem.description ?? ""
    self.author = feedItem.iTunes?.iTunesAuthor ?? ""
    self.imageUrl = feedItem.iTunes?.iTunesImage?.attributes?.href
  }

}
