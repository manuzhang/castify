//
//  HomeView.swift
//  Podcasts
//
//  Created by Alberto on 08/06/2019.
//  Copyright © 2019 com.github.albertopeam. All rights reserved.
//

import SwiftUI

struct HomeView : View {
        
    var body: some View {
        TabView {
            SearchView()
                .tabItem {
                    Text("Search")
                }
                .tag(0)
            PodcastsView()
                .tabItem {
                    Text("Play")
                }
                .tag(1)
        }
        .font(.headline)
    }
}

#if DEBUG
struct HomeView_Previews : PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}
#endif
