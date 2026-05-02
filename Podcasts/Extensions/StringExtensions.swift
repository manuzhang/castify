import Foundation

extension String {

  var httpsUrlString: String {
    self.contains("https") ? self : self.replacingOccurrences(of: "http", with: "https")
  }

  var URLEscapedString: String {
    self.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlHostAllowed)!
  }

  var strippingHTML: String {
    let withoutTags = replacingOccurrences(
      of: "\\s*<[^>]+>\\s*",
      with: " ",
      options: .regularExpression,
      range: nil
    )

    return withoutTags.replacingOccurrences(
      of: "\\s+",
      with: " ",
      options: .regularExpression,
      range: nil
    )
    .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var fileSystemSafeName: String {
    let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
      .union(.newlines)
      .union(.controlCharacters)
    let components = self.components(separatedBy: invalidCharacters)
    let fileName = components
      .joined(separator: "-")
      .replacingOccurrences(
        of: "\\s+",
        with: " ",
        options: .regularExpression,
        range: nil
      )
      .trimmingCharacters(in: .whitespacesAndNewlines)

    return fileName.isEmpty ? UUID().uuidString : fileName
  }

}
