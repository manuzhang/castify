import Foundation

extension Date {

  var formatMedium: String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.locale = Locale(identifier: LocalizationService.shared.localeIdentifier)
    return formatter.string(from: self)
  }

  var formatMediumDateTime: String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.locale = Locale(identifier: LocalizationService.shared.localeIdentifier)
    return formatter.string(from: self)
  }

}

extension TimeInterval {

  var podcastDuration: String {
    let totalSeconds = max(0, Int(self))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60

    return LocalizationService.shared.podcastDuration(hours: hours, minutes: minutes)
  }

}
