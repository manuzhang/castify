import SwiftUI

struct SearchRow: View {
    @ObservedObject var viewModel: SearchViewModel
    @State var podcast: Podcast

    var body: some View {
        HStack {
/*            viewModel.userImages[podcast].map { image in
                Image(uiImage: image)
                        .frame(width: 44, height: 44)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.black, lineWidth: 1))
            }*/

            Text("podcast")
                    .font(Font.system(size: 18).bold())

            Spacer()
        }
                .frame(height: 60)
    }
}