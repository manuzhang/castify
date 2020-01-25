import Foundation

extension String {

  var httpsUrlString: String {
    self.contains("https") ? self : self.replacingOccurrences(of: "http", with: "https")
  }

  var URLEscapedString: String {
    self.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlHostAllowed)!
  }

}
