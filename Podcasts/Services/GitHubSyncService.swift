import Foundation

enum GitHubSyncError: LocalizedError {
  case invalidURL
  case invalidResponse
  case requestFailed(statusCode: Int, message: String)

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return LocalizationService.shared.text(.githubSyncInvalidURL)
    case .invalidResponse:
      return LocalizationService.shared.text(.githubSyncInvalidResponse)
    case .requestFailed(let statusCode, let message):
      return LocalizationService.shared.githubSyncError(statusCode: statusCode, message: message)
    }
  }
}

final class GitHubSyncService {

  private let owner: String
  private let repo: String
  private let path: String
  private let branch: String
  private let session: URLSession

  init(owner: String = "manuzhang",
       repo: String = "MyPodcasts",
       path: String = "subscriptions.opml",
       branch: String = "main",
       session: URLSession = .shared) {
    self.owner = owner
    self.repo = repo
    self.path = path
    self.branch = branch
    self.session = session
  }

  func sync(opmlData: Data,
            token: String,
            completion: @escaping (Result<Void, Error>) -> Void) {
    fetchCurrentFileSHA(token: token) { [weak self] result in
      switch result {
      case .success(let sha):
        self?.updateFile(opmlData: opmlData, token: token, sha: sha, completion: completion)
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  private func fetchCurrentFileSHA(token: String,
                                   completion: @escaping (Result<String?, Error>) -> Void) {
    guard let request = makeRequest(method: "GET", token: token) else {
      completion(.failure(GitHubSyncError.invalidURL))
      return
    }

    session.dataTask(with: request) { data, response, error in
      if let error = error {
        completion(.failure(error))
        return
      }

      guard let httpResponse = response as? HTTPURLResponse else {
        completion(.failure(GitHubSyncError.invalidResponse))
        return
      }

      if httpResponse.statusCode == 404 {
        completion(.success(nil))
        return
      }

      guard 200..<300 ~= httpResponse.statusCode, let data = data else {
        completion(.failure(self.error(from: data, statusCode: httpResponse.statusCode)))
        return
      }

      do {
        let response = try JSONDecoder().decode(GitHubContentResponse.self, from: data)
        completion(.success(response.sha))
      } catch {
        completion(.failure(error))
      }
    }.resume()
  }

  private func updateFile(opmlData: Data,
                          token: String,
                          sha: String?,
                          completion: @escaping (Result<Void, Error>) -> Void) {
    guard var request = makeRequest(method: "PUT", token: token) else {
      completion(.failure(GitHubSyncError.invalidURL))
      return
    }

    do {
      let body = GitHubUpdateFileRequest(
        message: "Sync Castify subscribed podcasts",
        content: opmlData.base64EncodedString(),
        sha: sha,
        branch: branch
      )
      request.httpBody = try JSONEncoder().encode(body)
    } catch {
      completion(.failure(error))
      return
    }

    session.dataTask(with: request) { data, response, error in
      if let error = error {
        completion(.failure(error))
        return
      }

      guard let httpResponse = response as? HTTPURLResponse else {
        completion(.failure(GitHubSyncError.invalidResponse))
        return
      }

      guard 200..<300 ~= httpResponse.statusCode else {
        completion(.failure(self.error(from: data, statusCode: httpResponse.statusCode)))
        return
      }

      completion(.success(()))
    }.resume()
  }

  private func makeRequest(method: String, token: String) -> URLRequest? {
    guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/contents/\(path)") else {
      return nil
    }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    return request
  }

  private func error(from data: Data?, statusCode: Int) -> Error {
    let fallback = HTTPURLResponse.localizedString(forStatusCode: statusCode)
    guard let data = data,
          let response = try? JSONDecoder().decode(GitHubErrorResponse.self, from: data) else {
      return GitHubSyncError.requestFailed(statusCode: statusCode, message: fallback)
    }

    return GitHubSyncError.requestFailed(statusCode: statusCode, message: response.message)
  }
}

private struct GitHubContentResponse: Decodable {
  let sha: String
}

private struct GitHubUpdateFileRequest: Encodable {
  let message: String
  let content: String
  let sha: String?
  let branch: String
}

private struct GitHubErrorResponse: Decodable {
  let message: String
}
