import Foundation
import SwiftUI

struct PlayerView: View {

  @ObservedObject var player: Player

  init(player: Player = Container.player) {
    self.player = player
  }

  var body: some View {
    Group {
      if player.hasEpisodes {
        VStack(spacing: 10) {
          Slider(
            value: Binding(
              get: { Double(min(max(self.player.progress, 0), 1)) },
              set: { self.player.progress = Float($0) }
            ),
            in: 0...1,
            onEditingChanged: { editing in
              if !editing {
                self.player.seek(to: self.player.progress)
              }
            }
          )
          .accentColor(.blue)

          HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
              Text(player.current?.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
              Text(player.current?.author)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(timeSummary)
              .font(.caption)
              .foregroundColor(.secondary)
              .lineLimit(1)
          }

          HStack(spacing: 24) {
            Button(action: {
              self.player.previous()
            }) {
              Image(systemName: "backward.end.fill")
            }
            .accessibility(label: Text("Previous episode"))

            Button(action: {
              self.player.seek(by: -15)
            }) {
              Image(systemName: "gobackward.15")
            }
            .accessibility(label: Text("Back 15 seconds"))

            Button(action: togglePlayback) {
              Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 44, weight: .regular))
            }
            .accessibility(label: Text(player.isPlaying ? "Pause" : "Play"))

            Button(action: {
              self.player.seek(by: 30)
            }) {
              Image(systemName: "goforward.30")
            }
            .accessibility(label: Text("Forward 30 seconds"))

            Button(action: {
              self.player.next()
            }) {
              Image(systemName: "forward.end.fill")
            }
            .accessibility(label: Text("Next episode"))
          }
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color(.secondarySystemBackground))
      }
    }
  }

  private var timeSummary: String {
    guard player.duration > 0 else {
      return formatTime(player.elapsedTime)
    }

    return "\(formatTime(player.elapsedTime)) / \(formatTime(player.duration))"
  }

  private func togglePlayback() {
    switch player.state {
    case .empty:
      break
    case .idle, .paused, .finish:
      player.play()
    case .playing:
      player.pause()
    }
  }

  private func formatTime(_ time: TimeInterval) -> String {
    guard time.isFinite && !time.isNaN else {
      return "0:00"
    }

    let totalSeconds = max(0, Int(time))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    return String(format: "%d:%02d", minutes, seconds)
  }

}

extension Text {
  init(_ string: String?) {
    self.init(verbatim: string ?? "")
  }
}
