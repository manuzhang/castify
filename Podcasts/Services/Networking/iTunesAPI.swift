import Foundation

enum ITunesAPI {
  case search(term: String, countryCode: String)
  case lookup(ids: [Int], countryCode: String)
  case topPodcasts(genreId: String?, limit: Int, storefrontPath: String)
}

extension ITunesAPI {

  var urlRequest: URLRequest? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "itunes.apple.com"
    switch self {
    case .search(let term, let countryCode):
      components.path = "/search"
      components.queryItems = [
        URLQueryItem(name: "term", value: term),
        URLQueryItem(name: "media", value: "podcast"),
        URLQueryItem(name: "country", value: countryCode)
      ]
    case .lookup(let ids, let countryCode):
      components.path = "/lookup"
      components.queryItems = [
        URLQueryItem(name: "id", value: ids.map(String.init).joined(separator: ",")),
        URLQueryItem(name: "country", value: countryCode)
      ]
    case .topPodcasts(let genreId, let limit, let storefrontPath):
      var path = "/\(storefrontPath)/rss/toppodcasts/limit=\(limit)"
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
