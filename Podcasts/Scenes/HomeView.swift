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
          Image(systemName: "list.dash")
          Text("Podcasts")
        }.tag(0)
      SearchView()
        .tabItem {
          Image(systemName: "magnifyingglass")
          Text("Search")
        }.imageScale(.large).tag(1)
    }.font(.headline)
  }
}

