//
// Created by doriadong on 2020/1/27.
// Copyright (c) 2020 com.github.albertopeam. All rights reserved.
//

import Foundation

final class PodcastsViewModel: ObservableObject {

  @Published private(set) var podcasts = [Podcast]()
  fileprivate let podcastsService = PodcastsService()

  func updatePodcasts() {
    let pods = podcastsService.subscribedPodcasts
    self.podcasts = Array(Set(pods))
  }
}