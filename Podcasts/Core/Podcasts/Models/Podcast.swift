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

//  func encode(to encoder: Encoder) throws {
//    trackId.encode(to: coder)
//    trackName.encode(to: coder)
//    trackCount.encode(to: coder)
//    artistName.encode(to: coder)
//    artworkUrl100.encode(to: coder)
//    feedUrl.encode(to: coder)
//  }

  func thumbnail() -> URL? {
    URL(string: artworkUrl100)
  }

//  init?(coder aDecoder: NSCoder) {
//    self.trackId = aDecoder.decodeObject(forKey: Keys.trackIdKey) as? Int
//    self.trackName = aDecoder.decodeObject(forKey: Keys.trackNameKey) as? String
//    self.trackCount = aDecoder.decodeObject(forKey: Keys.trackCountKey) as? Int
//    self.artistName = aDecoder.decodeObject(forKey: Keys.artistNameKey) as? String
//    self.artworkUrl100 = aDecoder.decodeObject(forKey: Keys.artworkKey) as? String
//    self.feedUrl = aDecoder.decodeObject(forKey: Keys.feedKey) as? String
//  }
    
//  private let uuid: UUID = UUID()
//
//  override var hash: Int {
//    trackId?.hashValue ?? uuid.hashValue
//  }
//
//  override func isEqual(_ object: Any?) -> Bool {
//    guard let object = object as? Podcast else {
//      return false
//    }
//    if self === object {
//      return true
//    }
//    if type(of: self) != type(of: object) {
//      return false
//    }
//    if self.hash != object.hash {
//      return false
//    }
//    return true
//  }
}

//private extension Podcast {
//
//  enum Keys {
//    static let trackIdKey = "trackId"
//    static let trackNameKey = "trackName"
//    static let trackCountKey = "trackCount"
//    static let artistNameKey = "artistName"
//    static let artworkKey = "artwork"
//    static let feedKey = "feed"
//  }
//
//}
