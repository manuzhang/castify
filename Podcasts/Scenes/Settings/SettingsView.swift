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

        Section(header: Text(localization.text(.listeningStats))) {
          HStack {
            Image(systemName: "clock")
            Text(localization.text(.totalListeningTime))
            Spacer()
            Text(viewModel.totalListeningTimeText)
              .foregroundColor(.secondary)
          }

          HStack {
            Image(systemName: "checkmark.circle")
            Text(localization.text(.episodesFinished))
            Spacer()
            Text("\(viewModel.finishedEpisodeCount)")
              .foregroundColor(.secondary)
          }

          HStack {
            Image(systemName: "calendar")
            Text(localization.text(.lastListened))
            Spacer()
            Text(viewModel.lastListenedText)
              .foregroundColor(.secondary)
          }
        }

        Section(header: Text(localization.text(.downloads))) {
          Toggle(
            isOn: Binding(
              get: { self.viewModel.autoDownloadEnabled },
              set: { self.viewModel.setAutoDownloadEnabled($0) }
            ),
            label: {
              HStack {
                Image(systemName: "arrow.down.circle")
                Text(localization.text(.autoDownloadEpisodes))
              }
            }
          )

          Toggle(
            isOn: Binding(
              get: { self.viewModel.autoDownloadWifiOnly },
              set: { self.viewModel.setAutoDownloadWifiOnly($0) }
            ),
            label: {
              HStack {
                Image(systemName: "wifi")
                Text(localization.text(.autoDownloadWifiOnly))
              }
            }
          )
          .disabled(!viewModel.autoDownloadEnabled)

          Stepper(
            value: Binding(
              get: { self.viewModel.autoDownloadEpisodeLimit },
              set: { self.viewModel.setAutoDownloadEpisodeLimit($0) }
            ),
            in: PodcastsService.autoDownloadEpisodeLimitRange,
            label: {
              HStack {
                Text(localization.text(.episodesPerPodcast))
                Spacer()
                Text("\(viewModel.autoDownloadEpisodeLimit)")
                  .foregroundColor(.secondary)
              }
            }
          )
          .disabled(!viewModel.autoDownloadEnabled)
        }

        Section(header: Text(localization.text(.storage))) {
          HStack {
            Text(localization.text(.downloadedEpisodes))
            Spacer()
            Text("\(viewModel.downloadedEpisodeCount)")
              .foregroundColor(.secondary)
          }

          HStack {
            Text(localization.text(.storageUsed))
            Spacer()
            Text(viewModel.storageUsedText)
              .foregroundColor(.secondary)
          }

          Button(action: {
            self.viewModel.clearDownloads()
          }, label: {
            HStack {
              Image(systemName: "trash")
              Text(localization.text(.clearDownloads))
            }
          })
          .disabled(viewModel.downloadedEpisodeCount == 0)
        }

        Section(header: Text(localization.text(.githubSync))) {
          SecureField(localization.text(.githubToken), text: $viewModel.githubTokenInput)
            .autocapitalization(.none)
            .disableAutocorrection(true)

          Button(action: {
            self.viewModel.saveGitHubToken()
          }, label: {
            HStack {
              Image(systemName: "key")
              Text(localization.text(.saveGitHubToken))
            }
          })
          .disabled(viewModel.githubTokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

          Toggle(
            isOn: Binding(
              get: { self.viewModel.githubAutoSyncEnabled },
              set: { self.viewModel.setGitHubAutoSyncEnabled($0) }
            ),
            label: {
              HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text(localization.text(.automaticGitHubSync))
              }
            }
          )
          .disabled(!viewModel.githubTokenSaved)

          HStack {
            Image(systemName: "clock.arrow.circlepath")
            Text(localization.text(.githubLastSync))
            Spacer()
            Text(viewModel.githubLastSyncText)
              .foregroundColor(.secondary)
          }

          if let message = viewModel.githubSyncMessage {
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
