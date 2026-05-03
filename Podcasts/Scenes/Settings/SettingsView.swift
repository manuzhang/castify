import SwiftUI

struct SettingsView: View {

  @ObservedObject var viewModel = SettingsViewModel()
  @State private var showingOPMLPicker = false

  var body: some View {
    NavigationView {
      Form {
        Section(header: Text("Library")) {
          Button(action: {
            self.showingOPMLPicker = true
          }, label: {
            HStack {
              Image(systemName: "square.and.arrow.down")
              Text("Import OPML")
            }
          })

          if viewModel.isImporting {
            Text("Importing...")
              .foregroundColor(.secondary)
          }

          if let message = viewModel.importMessage {
            Text(message)
              .font(.subheadline)
              .foregroundColor(.secondary)
          }
        }

        Section(header: Text("Subscriptions")) {
          HStack {
            Text("Subscribed podcasts")
            Spacer()
            Text("\(viewModel.subscriptionCount)")
              .foregroundColor(.secondary)
          }
        }
      }
      .navigationBarTitle(Text("Settings"))
      .onAppear {
        self.viewModel.refresh()
      }
      .sheet(isPresented: $showingOPMLPicker) {
        OPMLDocumentPicker(
          onPick: { url in
            self.showingOPMLPicker = false
            self.viewModel.importOPML(from: url)
          },
          onCancel: {
            self.showingOPMLPicker = false
          }
        )
      }
    }
  }
}
