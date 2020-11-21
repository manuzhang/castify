import Foundation

extension Date {

  var formatMedium: String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter.string(from: self)
  }

}

