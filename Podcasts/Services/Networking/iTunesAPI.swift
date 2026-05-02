import Foundation

enum ITunesAPI {
  case search(term: String)
  case lookup(ids: [Int])
  case topPodcasts(genreId: String?, limit: Int)
}

extension ITunesAPI {

  var urlRequest: URLRequest? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "itunes.apple.com"
    switch self {
    case .search(let term):
      components.path = "/search"
      components.queryItems = [
        URLQueryItem(name: "term", value: term),
        URLQueryItem(name: "media", value: "podcast")
      ]
    case .lookup(let ids):
      components.path = "/lookup"
      components.queryItems = [
        URLQueryItem(name: "id", value: ids.map(String.init).joined(separator: ","))
      ]
    case .topPodcasts(let genreId, let limit):
      var path = "/us/rss/toppodcasts/limit=\(limit)"
      if let genreId = genreId {
        path += "/genre=\(genreId)"
      }
      components.path = path + "/json"
    }

    guard let url = components.url else {
      return nil
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }
}
