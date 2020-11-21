import Moya

enum ITunesAPI {
  case search(term: String)
}

extension ITunesAPI: TargetType {

  var baseURL: URL {
    guard let url = URL(string: "https://itunes.apple.com/") else {
      fatalError("Error in base url: https://itunes.apple.com/")
    }
    return url
  }

  var path: String {
    switch self {
    case .search:
      return "/search"
    }
  }

  var method: Method {
    .get
  }

  var sampleData: Data {
    Data()
  }

  var task: Task {
    switch self {
    case .search(let term):
      let parameters = ["term": term, "media": "podcast"]
      return .requestParameters(parameters: parameters, encoding: URLEncoding.default)
    }
  }

  var headers: [String: String]? {
    ["Content-type": "application/json"]
  }

}
