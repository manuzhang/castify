import Foundation

extension Date {

  var formatMedium: String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter.string(from: self)
  }

}

extension TimeInterval {

  var podcastDuration: String {
    let totalSeconds = max(0, Int(self))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60

    if hours > 0 {
      return "\(hours)h \(minutes)m"
    }

    return "\(minutes)m"
  }

}
