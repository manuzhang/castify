import SwiftUI

struct DownloadProgressView: UIViewRepresentable {

  typealias UIViewType = UIProgressView
  private let progress: Float

  init(progress: Float = 0) {
    self.progress = progress
  }

  func makeUIView(context: UIViewRepresentableContext<DownloadProgressView>) -> UIProgressView {
    let progressView = UIProgressView.init(frame: CGRect.zero)
    progressView.progress = progress
    return progressView
  }

  func updateUIView(_ uiView: UIProgressView, context: UIViewRepresentableContext<DownloadProgressView>) {
    uiView.setProgress(progress, animated: true)
  }

}
