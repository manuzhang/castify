import Foundation

final class NetworkingService: NSObject {

  fileprivate var podcastsService: PodcastsService?
  private lazy var downloadSession: URLSession = URLSession(
    configuration: .default,
    delegate: self,
    delegateQueue: nil
  )
  private var downloadProgressHandlers = [Int: (Progress) -> Void]()
  private var downloadCompletionHandlers = [Int: (URL?, Error?) -> Void]()
  private var downloadDestinations = [Int: URL]()
  private var downloadedFileURLs = [Int: URL]()
  private let downloadStateQueue = DispatchQueue(label: "com.castify.download-state")

  init(podcastsService: PodcastsService = .init()) {
    self.podcastsService = podcastsService
    super.init()
  }

}

private struct TopPodcastsResponse: Decodable {
  let feed: Feed

  struct Feed: Decodable {
    let entry: [Entry]?
  }

  struct Entry: Decodable {
    let id: Identifier
  }

  struct Identifier: Decodable {
    let attributes: Attributes
  }

  struct Attributes: Decodable {
    let podcastId: String

    enum CodingKeys: String, CodingKey {
      case podcastId = "im:id"
    }
  }
}

// MARK: - Fetching podcasts
extension NetworkingService {

  func fetchPodcasts(searchText: String, completionHandler: @escaping ([Podcast]) -> Void) {
    guard let request = ITunesAPI.search(term: searchText).urlRequest else {
      completionHandler([])
      return
    }

    URLSession.shared.dataTask(with: request) { data, response, error in
      if let error = error {
        print("Failed to fetch podcasts:", error.localizedDescription)
        DispatchQueue.main.async {
          completionHandler([])
        }
        return
      }

      guard let httpResponse = response as? HTTPURLResponse,
            200..<300 ~= httpResponse.statusCode,
            let data = data else {
        print("Failed to fetch podcasts: invalid response")
        DispatchQueue.main.async {
          completionHandler([])
        }
        return
      }

      do {
        let searchResult = try JSONDecoder().decode(SearchResult.self, from: data)
        DispatchQueue.main.async {
          completionHandler(searchResult.results)
        }
      } catch {
        print("Failed to decode podcast search response:", error)
        DispatchQueue.main.async {
          completionHandler([])
        }
      }
    }.resume()
  }

  func fetchTopPodcasts(genreId: String?, limit: Int = 50, completionHandler: @escaping ([Podcast]) -> Void) {
    guard let request = ITunesAPI.topPodcasts(genreId: genreId, limit: limit).urlRequest else {
      completionHandler([])
      return
    }

    URLSession.shared.dataTask(with: request) { data, response, error in
      if let error = error {
        print("Failed to fetch top podcasts:", error.localizedDescription)
        DispatchQueue.main.async {
          completionHandler([])
        }
        return
      }

      guard let httpResponse = response as? HTTPURLResponse,
            200..<300 ~= httpResponse.statusCode,
            let data = data else {
        print("Failed to fetch top podcasts: invalid response")
        DispatchQueue.main.async {
          completionHandler([])
        }
        return
      }

      do {
        let response = try JSONDecoder().decode(TopPodcastsResponse.self, from: data)
        let ids = response.feed.entry?
          .compactMap { Int($0.id.attributes.podcastId) } ?? []
        self.fetchPodcasts(ids: ids, completionHandler: completionHandler)
      } catch {
        print("Failed to decode top podcast response:", error)
        DispatchQueue.main.async {
          completionHandler([])
        }
      }
    }.resume()
  }

  private func fetchPodcasts(ids: [Int], completionHandler: @escaping ([Podcast]) -> Void) {
    guard !ids.isEmpty,
          let request = ITunesAPI.lookup(ids: ids).urlRequest else {
      completionHandler([])
      return
    }

    URLSession.shared.dataTask(with: request) { data, response, error in
      if let error = error {
        print("Failed to lookup podcasts:", error.localizedDescription)
        DispatchQueue.main.async {
          completionHandler([])
        }
        return
      }

      guard let httpResponse = response as? HTTPURLResponse,
            200..<300 ~= httpResponse.statusCode,
            let data = data else {
        print("Failed to lookup podcasts: invalid response")
        DispatchQueue.main.async {
          completionHandler([])
        }
        return
      }

      do {
        let searchResult = try JSONDecoder().decode(SearchResult.self, from: data)
        let podcastsById = Dictionary(uniqueKeysWithValues: searchResult.results.map { ($0.trackId, $0) })
        let orderedPodcasts = ids.compactMap { podcastsById[$0] }
          .filter { !$0.feedUrl.isEmpty }
        DispatchQueue.main.async {
          completionHandler(orderedPodcasts)
        }
      } catch {
        print("Failed to decode podcast lookup response:", error)
        DispatchQueue.main.async {
          completionHandler([])
        }
      }
    }.resume()
  }

  func fetchPodcastFeed(url: URL, completionHandler: @escaping (Result<ParsedPodcastFeed, Error>) -> Void) {
    URLSession.shared.dataTask(with: url) { data, response, error in
      if let error = error {
        DispatchQueue.main.async {
          completionHandler(.failure(error))
        }
        return
      }

      guard let httpResponse = response as? HTTPURLResponse,
            200..<300 ~= httpResponse.statusCode,
            let data = data else {
        DispatchQueue.main.async {
          completionHandler(.failure(PodcastFeedParserError.invalidFeed))
        }
        return
      }

      do {
        let feed = try PodcastFeedParser().parse(data: data)
        DispatchQueue.main.async {
          completionHandler(.success(feed))
        }
      } catch {
        DispatchQueue.main.async {
          completionHandler(.failure(error))
        }
      }
    }.resume()
  }
}

// MARK: - Downloading episodes
extension NetworkingService {

  typealias EpisodeDownloadComplete = (fileUrl: String, episodeTitle: String)

  func downloadEpisode(_ episode: Episode, _ handler: @escaping (Progress) -> Void) {
    print("Downloading episode at stream url:", episode.streamUrl)
    guard let url = URL(string: episode.streamUrl) else {
      print("Invalid episode stream url: ", episode.streamUrl)
      return
    }

    let task = downloadSession.downloadTask(with: url)
    let destination = destinationURL(for: episode, sourceURL: url)
    let taskIdentifier = task.taskIdentifier

    downloadStateQueue.sync {
      downloadProgressHandlers[taskIdentifier] = handler
      downloadDestinations[taskIdentifier] = destination
      downloadCompletionHandlers[taskIdentifier] = { [weak self] fileURL, error in
        guard let self = self else {
          return
        }

        if let fileURL = fileURL, error == nil {
          self.saveDownloadedEpisode(episode, fileURL: fileURL)
        } else {
          print("Failed to download episode from url: ", episode.streamUrl)
        }
      }
    }

    task.resume()
  }

  private func destinationURL(for episode: Episode, sourceURL: URL) -> URL {
    let fileManager = FileManager.default
    let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let episodesDirectory = documentsURL.appendingPathComponent("Episodes", isDirectory: true)
    try? fileManager.createDirectory(at: episodesDirectory, withIntermediateDirectories: true, attributes: nil)

    let fileExtension = sourceURL.pathExtension.isEmpty ? "mp3" : sourceURL.pathExtension
    let dateSuffix = Int(episode.pubDate.timeIntervalSince1970)
    let fileName = episode.title.fileSystemSafeName + "-\(dateSuffix)." + fileExtension
    return episodesDirectory.appendingPathComponent(fileName)
  }

  private func saveDownloadedEpisode(_ episode: Episode, fileURL: URL) {
    let path = fileURL.path
    print("Downloaded episode to: ", path)
    let episodeDownloadComplete = EpisodeDownloadComplete(fileUrl: path,
      episodeTitle: episode.title)
    NotificationCenter.default.post(name: .downloadComplete, object: episodeDownloadComplete, userInfo: nil)

    var downloadedEpisodes = podcastsService?.downloadedEpisodes ?? []
    let downloadedEpisode = episode
    downloadedEpisode.fileUrl = path
    downloadedEpisodes.removeAll(where: { $0 == episode })
    downloadedEpisodes.append(downloadedEpisode)

    do {
      let data = try JSONEncoder().encode(downloadedEpisodes)
      UserDefaults.standard.set(data, forKey: UserDefaults.downloadedEpisodesKey)
    } catch let downloadingError {
      print("Failed to encode downloaded episodes with file url update:", downloadingError)
    }
  }
}

extension NetworkingService: URLSessionDownloadDelegate {

  func urlSession(_ session: URLSession,
                  downloadTask: URLSessionDownloadTask,
                  didWriteData bytesWritten: Int64,
                  totalBytesWritten: Int64,
                  totalBytesExpectedToWrite: Int64) {
    guard totalBytesExpectedToWrite > 0 else {
      return
    }

    let progress = Progress(totalUnitCount: totalBytesExpectedToWrite)
    progress.completedUnitCount = totalBytesWritten

    let taskIdentifier = downloadTask.taskIdentifier
    let handler = downloadStateQueue.sync {
      downloadProgressHandlers[taskIdentifier]
    }

    DispatchQueue.main.async {
      handler?(progress)
    }
  }

  func urlSession(_ session: URLSession,
                  downloadTask: URLSessionDownloadTask,
                  didFinishDownloadingTo location: URL) {
    let taskIdentifier = downloadTask.taskIdentifier
    let destination = downloadStateQueue.sync {
      downloadDestinations[taskIdentifier]
    }

    guard let destinationURL = destination else {
      return
    }

    do {
      if FileManager.default.fileExists(atPath: destinationURL.path) {
        try FileManager.default.removeItem(at: destinationURL)
      }
      try FileManager.default.moveItem(at: location, to: destinationURL)
      downloadStateQueue.sync {
        downloadedFileURLs[taskIdentifier] = destinationURL
      }
    } catch {
      print("Failed to move downloaded episode: ", error)
    }
  }

  func urlSession(_ session: URLSession,
                  task: URLSessionTask,
                  didCompleteWithError error: Error?) {
    let taskIdentifier = task.taskIdentifier
    var progressHandler: ((Progress) -> Void)?
    var completion: ((URL?, Error?) -> Void)?
    var fileURL: URL?

    downloadStateQueue.sync {
      progressHandler = downloadProgressHandlers[taskIdentifier]
      completion = downloadCompletionHandlers[taskIdentifier]
      fileURL = downloadedFileURLs[taskIdentifier]
      downloadProgressHandlers[taskIdentifier] = nil
      downloadCompletionHandlers[taskIdentifier] = nil
      downloadDestinations[taskIdentifier] = nil
      downloadedFileURLs[taskIdentifier] = nil
    }

    DispatchQueue.main.async {
      if error == nil, fileURL != nil {
        let progress = Progress(totalUnitCount: 1)
        progress.completedUnitCount = 1
        progressHandler?(progress)
      }
      completion?(fileURL, error)
    }
  }
}
