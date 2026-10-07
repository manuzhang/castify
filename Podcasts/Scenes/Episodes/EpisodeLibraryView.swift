import SwiftUI

struct EpisodeLibraryView: View {
  @ObservedObject var viewModel: EpisodeLibraryViewModel
  @EnvironmentObject var localization: LocalizationService

  init(viewModel: EpisodeLibraryViewModel = .init()) {
    self.viewModel = viewModel
  }

  var body: some View {
    List {
      EpisodeFilterControls(filters: $viewModel.filters, podcasts: viewModel.podcasts)

      if viewModel.isRefreshing {
        HStack {
          Spinner()
          Text(localization.text(.loadingEpisodes))
        }
      }
      if !viewModel.failedPodcasts.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text(localization.text(.episodeRefreshFailed))
          Text(viewModel.failedPodcasts.joined(separator: ", "))
        }
        .font(.footnote)
        .foregroundColor(.secondary)
      }

      Section(header: Text("\(localization.text(.episodes)) (\(viewModel.filteredEntries.count))")) {
        if viewModel.filteredEntries.isEmpty && !viewModel.isRefreshing {
          Text(localization.text(viewModel.podcasts.isEmpty ? .searchForShows :
            (viewModel.filters == EpisodeFilters() ? .noEpisodesAvailable : .noMatchingEpisodes)))
            .foregroundColor(.secondary)
        }
        ForEach(viewModel.filteredEntries) { item in
          NavigationLink(destination: EpisodeView(episode: item.episode,
            episodes: self.viewModel.filteredEntries.map { $0.episode })) {
            VStack(alignment: .leading, spacing: 2) {
              HStack {
                Text(item.podcast.trackName)
                  .lineLimit(1)
                if item.isDownloaded {
                  Image(systemName: "arrow.down.circle.fill")
                    .accessibility(label: Text(self.localization.text(.downloaded)))
                }
              }
              .font(.caption)
              .foregroundColor(.secondary)
              EpisodeRow(episode: item.episode, playbackState: item.playbackState)
            }
          }
          .contextMenu {
            Button(action: { self.viewModel.togglePlayed(item) }) {
              Text(self.localization.text(item.playbackState?.played == true ? .markAsUnplayed : .markAsPlayed))
              Image(systemName: item.playbackState?.played == true ? "circle" : "checkmark.circle")
            }
          }
        }
      }
    }
    .listStyle(GroupedListStyle())
    .navigationBarTitle(Text(localization.text(.allEpisodes)), displayMode: .inline)
    .navigationBarItems(trailing: Button(action: viewModel.refresh) {
      Image(systemName: "arrow.clockwise")
    }
    .disabled(viewModel.isRefreshing)
    .accessibility(label: Text(localization.text(.refreshEpisodes))))
    .onAppear(perform: viewModel.appear)
    .onReceive(NotificationCenter.default.publisher(for: .episodePlaybackStateDidChange)) { _ in
      self.viewModel.reloadCachedEpisodes()
    }
    .onReceive(NotificationCenter.default.publisher(for: .downloadComplete)) { _ in
      self.viewModel.reloadCachedEpisodes()
    }
    .onReceive(NotificationCenter.default.publisher(for: .subscribedPodcastsDidChange)) { _ in
      self.viewModel.reloadCachedEpisodes()
    }
    .onReceive(NotificationCenter.default.publisher(for: .episodeLibraryDidChange)) { _ in
      self.viewModel.reloadCachedEpisodes()
    }
  }
}

struct EpisodeFilterControls: View {
  @Binding var filters: EpisodeFilters
  let podcasts: [Podcast]
  @EnvironmentObject var localization: LocalizationService

  var body: some View {
    Section(header: Text(localization.text(.episodeFilters))) {
      Toggle(localization.text(.unplayedOnly), isOn: $filters.unplayedOnly)
      Toggle(localization.text(.downloadedOnly), isOn: $filters.downloadedOnly)
      Picker(localization.text(.podcastFilter), selection: $filters.podcastFeedURL) {
        Text(localization.text(.allPodcasts)).tag("")
        ForEach(podcasts, id: \.feedUrl) { podcast in
          Text(podcast.trackName).tag(PodcastsService.normalizedFeedUrl(podcast.feedUrl))
        }
      }
      Picker(localization.text(.durationFilter), selection: $filters.duration) {
        ForEach(EpisodeDurationFilter.allCases, id: \.self) { duration in
          Text(self.localization.text(duration.text)).tag(duration)
        }
      }
      if filters != EpisodeFilters() {
        Button(localization.text(.resetEpisodeFilters)) { self.filters = EpisodeFilters() }
      }
    }
  }
}
