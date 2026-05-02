import UIKit.UIImage
import SwiftUI
import Combine

class ImagesLoader: ObservableObject {

  @Published private(set) var images = [URL: UIImage]()
  private var loadingURLs = Set<URL>()

  func load(url: URL?) {
    guard let url = url else {
      return
    }

    guard images[url] == nil && !loadingURLs.contains(url) else {
      return
    }

    loadingURLs.insert(url)
    URLSession.shared.dataTask(with: url) { data, _, _ in
      guard let data = data, let image = UIImage(data: data) else {
        DispatchQueue.main.async {
          self.loadingURLs.remove(url)
        }
        return
      }

      DispatchQueue.main.async {
        self.images[url] = image
        self.loadingURLs.remove(url)
      }
    }.resume()
  }

  func image(for url: URL?) -> UIImage {
    guard let url = url else {
      return UIImage.from(color: .gray)
    }
    guard let image = images[url] else {
      return UIImage.from(color: .gray)
    }
    return image
  }

}

struct RemoteImage: View {

  let url: URL?
  let contentMode: ContentMode
  @ObservedObject private var loader = ImagesLoader()

  init(url: URL?, contentMode: ContentMode = .fill) {
    self.url = url
    self.contentMode = contentMode
  }

  var body: some View {
    Image(uiImage: loader.image(for: url))
      .resizable()
      .aspectRatio(contentMode: contentMode)
      .onAppear {
        self.loader.load(url: self.url)
      }
  }
}
