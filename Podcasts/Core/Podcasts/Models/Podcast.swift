//
//  Podcast.swift
//  Search
//
//  Created by Eugene Karambirov on 21/09/2018.
//  Copyright © 2018 Eugene Karambirov. All rights reserved.
//

import Foundation

final class Podcast: NSObject, Decodable, NSCoding, Identifiable {

  var trackId: Int?
  var trackName: String?
  var artistName: String?
  var artworkUrl100: String?
  var trackCount: Int?
  var feedUrl: String?

  func encode(with aCoder: NSCoder) {
    aCoder.encode(trackId ?? 0, forKey: Keys.trackIdKey)
    aCoder.encode(trackName ?? "", forKey: Keys.trackNameKey)
    aCoder.encode(artistName ?? "", forKey: Keys.artistNameKey)
    aCoder.encode(artworkUrl100 ?? "", forKey: Keys.artworkKey)
    aCoder.encode(feedUrl ?? "", forKey: Keys.feedKey)
  }

  func thumbnail() -> URL? {
    artworkUrl100.flatMap { URL(string: $0) }
  }

  init?(coder aDecoder: NSCoder) {
    self.trackId = aDecoder.decodeObject(forKey: Keys.trackIdKey) as? Int
    self.trackName = aDecoder.decodeObject(forKey: Keys.trackNameKey) as? String
    self.artistName = aDecoder.decodeObject(forKey: Keys.artistNameKey) as? String
    self.artworkUrl100 = aDecoder.decodeObject(forKey: Keys.artworkKey) as? String
    self.feedUrl = aDecoder.decodeObject(forKey: Keys.feedKey) as? String
  }

  override var hash: Int {
    trackId?.hashValue ?? UUID().hashValue
  }

  override func isEqual(_ object: Any?) -> Bool {
    guard let object = object as? Podcast else {
      return false
    }
    if self === object {
      return true
    }
    if type(of: self) != type(of: object) {
      return false
    }
    if self.trackId != object.trackId {
      return false
    }
    return true
  }
}

private extension Podcast {

  enum Keys {
    static let trackIdKey = "trackIdKey"
    static let trackNameKey = "trackNameKey"
    static let artistNameKey = "artistNameKey"
    static let artworkKey = "artworkKey"
    static let feedKey = "feedKey"
  }

}
