import SwiftUI

struct SettingsView: View {

  @ObservedObject var viewModel = SettingsViewModel()
  @EnvironmentObject var localization: LocalizationService
  @State private var showingOPMLPicker = false

  var body: some View {
    NavigationView {
      Form {
        Section(header: Text(localization.text(.language))) {
          Picker(
            selection: Binding(
              get: { self.localization.language },
              set: { self.localization.setLanguage($0) }
            ),
            label: Text(localization.text(.language))
          ) {
            ForEach(AppLanguage.allCases) { language in
              Text(self.localization.title(for: language)).tag(language)
            }
          }
          .pickerStyle(SegmentedPickerStyle())
        }

        Section(header: Text(localization.text(.library))) {
          Button(action: {
            self.showingOPMLPicker = true
          }, label: {
            HStack {
              Image(systemName: "square.and.arrow.down")
              Text(localization.text(.importOPML))
            }
          })

          if viewModel.isImporting {
            Text(localization.text(.importing))
              .foregroundColor(.secondary)
          }

          if let message = viewModel.importMessage {
            Text(message)
              .font(.subheadline)
              .foregroundColor(.secondary)
          }
        }

        Section(header: Text(localization.text(.notifications))) {
          Toggle(
            isOn: Binding(
              get: { self.viewModel.notificationsEnabled },
              set: { self.viewModel.setNotificationsEnabled($0) }
            ),
            label: {
              HStack {
                Image(systemName: "bell")
                Text(localization.text(.notifications))
              }
            }
          )

          if let message = viewModel.notificationStatusMessage {
            Text(message)
              .font(.subheadline)
              .foregroundColor(.secondary)
          }
        }

        Section(header: Text(localization.text(.subscriptions))) {
          HStack {
            Text(localization.text(.subscribedPodcasts))
            Spacer()
            Text("\(viewModel.subscriptionCount)")
              .foregroundColor(.secondary)
          }
        }
      }
      .navigationBarTitle(Text(localization.text(.settings)))
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
