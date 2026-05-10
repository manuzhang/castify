import Foundation

extension String {

  var httpsUrlString: String {
    self.contains("https") ? self : self.replacingOccurrences(of: "http", with: "https")
  }

  var URLEscapedString: String {
    self.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlHostAllowed)!
  }

  var strippingHTML: String {
    var readableText = replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")

    readableText = readableText.replacingOccurrences(
      of: "(?is)<\\s*(script|style)\\b[^>]*>.*?</\\s*\\1\\s*>",
      with: "",
      options: .regularExpression,
      range: nil
    )
    readableText = readableText.replacingOccurrences(
      of: "(?s)<!--.*?-->",
      with: "",
      options: .regularExpression,
      range: nil
    )
    readableText = readableText.replacingOccurrences(
      of: "(?i)<\\s*br\\s*/?>",
      with: "\n",
      options: .regularExpression,
      range: nil
    )
    readableText = readableText.replacingOccurrences(
      of: "(?i)<\\s*li\\b[^>]*>",
      with: "- ",
      options: .regularExpression,
      range: nil
    )
    readableText = readableText.replacingOccurrences(
      of: "(?i)</\\s*li\\s*>",
      with: "\n",
      options: .regularExpression,
      range: nil
    )
    readableText = readableText.replacingOccurrences(
      of: "(?i)</\\s*(p|div|section|article|header|footer|h[1-6]|blockquote|ul|ol|pre|table|tr)\\s*>",
      with: "\n\n",
      options: .regularExpression,
      range: nil
    )
    readableText = readableText.replacingOccurrences(
      of: "(?i)<\\s*(p|div|section|article|header|footer|h[1-6]|blockquote|ul|ol|pre|table|tr)\\b[^>]*>",
      with: "\n",
      options: .regularExpression,
      range: nil
    )
    readableText = readableText.replacingOccurrences(
      of: "(?s)<[^>]+>",
      with: "",
      options: .regularExpression,
      range: nil
    )
    readableText = readableText.decodingHTMLEntities
      .replacingOccurrences(of: "\u{00a0}", with: " ")
    readableText = readableText.replacingOccurrences(
      of: "[ \\t]+",
      with: " ",
      options: .regularExpression,
      range: nil
    )
    readableText = readableText.replacingOccurrences(
      of: " *\\n *",
      with: "\n",
      options: .regularExpression,
      range: nil
    )
    readableText = readableText.replacingOccurrences(
      of: "\\n{3,}",
      with: "\n\n",
      options: .regularExpression,
      range: nil
    )

    return readableText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var decodingHTMLEntities: String {
    let pattern = "&#(\\d+);|&#x([0-9A-Fa-f]+);|&([A-Za-z][A-Za-z0-9]+);"

    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return self
    }

    let original = self as NSString
    let matches = regex.matches(
      in: self,
      range: NSRange(location: 0, length: original.length)
    )

    guard !matches.isEmpty else {
      return self
    }

    var decoded = self

    for match in matches.reversed() {
      guard let range = Range(match.range, in: decoded),
            let replacement = replacementEntity(for: match, in: original) else {
        continue
      }

      decoded.replaceSubrange(range, with: replacement)
    }

    return decoded
  }

  private func replacementEntity(for match: NSTextCheckingResult, in original: NSString) -> String? {
    if match.range(at: 1).location != NSNotFound {
      let decimalValue = original.substring(with: match.range(at: 1))
      guard let value = UInt32(decimalValue), let scalar = UnicodeScalar(value) else {
        return nil
      }

      return String(scalar)
    }

    if match.range(at: 2).location != NSNotFound {
      let hexValue = original.substring(with: match.range(at: 2))
      guard let value = UInt32(hexValue, radix: 16), let scalar = UnicodeScalar(value) else {
        return nil
      }

      return String(scalar)
    }

    if match.range(at: 3).location != NSNotFound {
      let name = original.substring(with: match.range(at: 3))
      return String.namedHTMLEntities[name.lowercased()]
    }

    return nil
  }

  private static let namedHTMLEntities: [String: String] = [
    "amp": "&",
    "apos": "'",
    "hellip": "\u{2026}",
    "laquo": "\u{00ab}",
    "ldquo": "\u{201c}",
    "lsquo": "\u{2018}",
    "mdash": "\u{2014}",
    "nbsp": " ",
    "ndash": "\u{2013}",
    "quot": "\"",
    "raquo": "\u{00bb}",
    "rdquo": "\u{201d}",
    "rsquo": "\u{2019}",
    "lt": "<",
    "gt": ">"
  ]

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
