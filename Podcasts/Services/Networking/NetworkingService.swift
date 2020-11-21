import Moya
import Alamofire
import FeedKit

final class NetworkingService {

  private var provider: MoyaProvider<ITunesAPI>?
  fileprivate var podcastsService: PodcastsService?

  init(provider: MoyaProvider<ITunesAPI> = .init(),
       podcastsService: PodcastsService = .init()) {
    self.provider = provider
    self.podcastsService = podcastsService
  }

}

// MARK: - Fetching podcasts
extension NetworkingService {

  func fetchPodcasts(searchText: String, completionHandler: @escaping ([Podcast]) -> Void) {
    provider?.request(.search(term: searchText)) { result in
      switch result {
      case .success(let response):
        do {
          let searchResult = try response.map(SearchResult.self)
          completionHandler(searchResult.results)
        } catch let decodingError {
          print("Failed to decode from " + response.description, decodingError)
        }
      case .failure(let error):
        print(error.errorDescription ?? "")
      }
    }
  }
}

// MARK: - Downloading episodes
extension NetworkingService {

  typealias EpisodeDownloadComplete = (fileUrl: String, episodeTitle: String)

  func downloadEpisode(_ episode: Episode, _ handler: @escaping (Progress) -> Void) {
    print("Downloading episode at stream url:", episode.streamUrl)

    let destination = DownloadRequest.suggestedDownloadDestination()

//    AF.download(episode.streamUrl, to: downloadRequest).downloadProgress { progress in
//      NotificationCenter.default.post(name: NSNotification.Name("downloadProgress"), object: nil,
//        userInfo: ["title": episode.title, "progress": progress.fractionCompleted])
//    }


    AF.download(episode.streamUrl, to: destination).downloadProgress { progress in
        handler(progress)
      }
      .response { response in
        debugPrint(response)
        if response.error == nil, let path = response.fileURL?.absoluteString {
          print("Downloaded episode to: ", path)
          let episodeDownloadComplete = EpisodeDownloadComplete(fileUrl: path,
            episode.title)
          NotificationCenter.default.post(name: .downloadComplete, object: episodeDownloadComplete, userInfo: nil)

          var downloadedEpisodes = self.podcastsService?.downloadedEpisodes
          var epi = episode
          epi.fileUrl = path
          downloadedEpisodes?.append(epi)
//      guard let index = downloadedEpisodes?.firstIndex(where: {
//        $0.title == episode.title
//          && $0.author == episode.author
//      }) else {
//        return
//      }
//      downloadedEpisodes?[index].fileUrl = response.fileURL?.absoluteString ?? ""

          do {
            let data = try JSONEncoder().encode(downloadedEpisodes)
            UserDefaults.standard.set(data, forKey: UserDefaults.downloadedEpisodesKey)
          } catch let downloadingError {
            print("Failed to encode downloaded episodes with file url update:", downloadingError)
          }
        } else {
          print("Failed to download episode from url: ", episode.streamUrl)
        }
      }
  }
}
