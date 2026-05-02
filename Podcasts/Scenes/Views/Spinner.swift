import SwiftUI

struct Spinner: UIViewRepresentable {

  func makeUIView(context: UIViewRepresentableContext<Spinner>) -> UIActivityIndicatorView {
    let spinner = UIActivityIndicatorView(style: .medium)
    spinner.hidesWhenStopped = true
    spinner.startAnimating()
    return spinner
  }

  func updateUIView(_ uiView: UIActivityIndicatorView, context: UIViewRepresentableContext<Spinner>) {
    if !uiView.isAnimating {
      uiView.startAnimating()
    }
  }

}

#if DEBUG
struct Spinner_Previews: PreviewProvider {
  static var previews: some View {
    Spinner()
  }
}
#endif
