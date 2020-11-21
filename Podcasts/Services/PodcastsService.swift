import Foundation

final class PodcastsService {

  // MARK: - Properties
  var subscribedPodcasts: [Podcast] {
    fetchSavedPodcasts()
  }

  var downloadedEpisodes: [Episode] {
    fetchDownloadedEpisodes()
  }

}

// MARK: - Methods
extension PodcastsService {

  func addPodcast(_ podcast: Podcast) {
    var podcasts = subscribedPodcasts
    podcasts.append(podcast)

    do {
      let data = try JSONEncoder().encode(podcasts)
      UserDefaults.standard.set(data, forKey: UserDefaults.subscribedPodcastsKey)
    } catch let error {
      print("Failed to add podcast: " + podcast.trackName, error)
    }
  }

  func deletePodcast(_ podcast: Podcast) {
    let podcasts = subscribedPodcasts
    let filteredPodcasts = podcasts.filter { pod -> Bool in
      pod.trackId != podcast.trackId
    }

    do {
      let data = try JSONEncoder().encode(filteredPodcasts)
      UserDefaults.standard.set(data, forKey: UserDefaults.subscribedPodcastsKey)
    } catch let error {
      print("Failed to delete podcast: " + podcast.trackName, error)
    }
  }

  func episodeDownloaded(_ episode: Episode) -> Bool {
    let episodes = downloadedEpisodes
    return episodes.contains(episode)
  }

  func deleteEpisode(_ episode: Episode) {
    let fileManager = FileManager()
    if let path = episode.fileUrl, fileManager.fileExists(atPath: path) {
      do {
        try fileManager.removeItem(atPath: path)
      } catch {
        print("Failed to delete episode file: " + path)
      }
    }

    let savedEpisodes = downloadedEpisodes
    let filteredEpisodes = savedEpisodes.filter { epi -> Bool in
      epi != episode
    }

    do {
      let data = try JSONEncoder().encode(filteredEpisodes)
      UserDefaults.standard.set(data, forKey: UserDefaults.downloadedEpisodesKey)
    } catch let encodeError {
      print("Failed to encode episode: ", encodeError)
    }
  }

}

// MARK: - Private
extension PodcastsService {

  fileprivate func fetchSavedPodcasts() -> [Podcast] {
    guard let data = UserDefaults.standard.data(forKey: UserDefaults.subscribedPodcastsKey) else {
      return []
    }

    do {
      return try JSONDecoder().decode([Podcast].self, from: data)
    } catch {
      return []
    }
  }

  fileprivate func fetchDownloadedEpisodes() -> [Episode] {
    guard let data = UserDefaults.standard.data(forKey: UserDefaults.downloadedEpisodesKey) else {
      return []
    }

    do {
      return try JSONDecoder().decode([Episode].self, from: data)
    } catch let decodeError {
      print("Failed to decode:", decodeError)
      return []
    }
  }

}
