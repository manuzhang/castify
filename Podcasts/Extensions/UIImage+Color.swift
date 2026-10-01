import UIKit.UIImage

extension UIImage {
  static func from(color: UIColor) -> UIImage {
    let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    format.preferredRange = .standard
    return UIGraphicsImageRenderer(size: rect.size, format: format).image { context in
      color.setFill()
      context.fill(rect)
    }
  }
}
