//
//  HomeView.swift
//  Search
//
//  Created by Alberto on 08/06/2019.
//  Copyright © 2019 com.github.albertopeam. All rights reserved.
//

import SwiftUI

struct HomeView: View {

  var body: some View {
    TabView {
      PodcastsView()
        .tabItem {
          Text("Podcasts")
        }.tag(0)
      SearchView()
        .tabItem {
          Text("Search")
        }.tag(1)
    }.font(.headline)
  }
}

