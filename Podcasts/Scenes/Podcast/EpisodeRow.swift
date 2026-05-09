import SwiftUI

struct EpisodeRow: View {

  let episode: Episode
  let playbackState: EpisodePlaybackState?
  @EnvironmentObject var localization: LocalizationService

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: statusIconName)
        .font(.system(size: 26))
        .foregroundColor(statusColor)
        .frame(width: 32, height: 32)

      VStack(alignment: .leading, spacing: 5) {
        Text(episode.title)
          .font(.headline)
          .foregroundColor(playbackState?.played == true ? .secondary : .primary)
          .lineLimit(2)
        HStack(spacing: 6) {
          Text(episode.pubDate.formatMedium)
          if let duration = episode.duration, duration > 0 {
            Text("·")
            Text(duration.podcastDuration)
          }
          Text("·")
          Text(statusText)
        }
        .font(.caption)
        .foregroundColor(.secondary)
      }
    }
    .padding(.vertical, 6)
  }

  private var statusIconName: String {
    if playbackState?.played == true {
      return "checkmark.circle.fill"
    }

    if playbackState?.hasResumePosition == true {
      return "play.circle.fill"
    }

    return "circle"
  }

  private var statusColor: Color {
    if playbackState?.played == true {
      return .green
    }

    return .blue
  }

  private var statusText: String {
    if playbackState?.played == true {
      return localization.text(.played)
    }

    if let state = playbackState, state.hasResumePosition {
      return "\(localization.text(.resumeAt)) \(formatTimestamp(state.position))"
    }

    return localization.text(.unplayed)
  }

  private func formatTimestamp(_ time: TimeInterval) -> String {
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
