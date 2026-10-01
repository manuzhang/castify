import XCTest
import UIKit
@testable import Castify

final class UIImageColorTests: XCTestCase {
  func testSolidColorPreservesOnePixelSizeAndColor() throws {
    let image = UIImage.from(color: .red)
    XCTAssertEqual(image.size, CGSize(width: 1, height: 1))
    XCTAssertEqual(image.scale, 1)
    let pixel = try rgbaPixel(image)
    XCTAssertEqual(pixel, [255, 0, 0, 255])
  }

  func testClearColorPreservesTransparency() throws {
    XCTAssertEqual(try rgbaPixel(UIImage.from(color: .clear)), [0, 0, 0, 0])
  }

  func testTranslucentColorPreservesAlpha() throws {
    let pixel = try rgbaPixel(UIImage.from(color: UIColor(red: 0, green: 1, blue: 0, alpha: 0.5)))
    XCTAssertEqual(pixel[0], 0)
    XCTAssertEqual(pixel[2], 0)
    XCTAssertEqual(Int(pixel[1]), 128, accuracy: 1)
    XCTAssertEqual(Int(pixel[3]), 128, accuracy: 1)
  }

  func testMissingArtworkReturnsOpaqueGrayPlaceholder() throws {
    let loader = ImagesLoader()
    let pixel = try rgbaPixel(loader.image(for: nil))
    XCTAssertEqual(pixel[0], pixel[1])
    XCTAssertEqual(pixel[1], pixel[2])
    XCTAssertGreaterThan(pixel[0], 0)
    XCTAssertLessThan(pixel[0], 255)
    XCTAssertEqual(pixel[3], 255)
  }

  func testUncachedArtworkReturnsTheSamePlaceholder() throws {
    let loader = ImagesLoader()
    let url = try XCTUnwrap(URL(string: "https://example.invalid/artwork.png"))
    XCTAssertEqual(try rgbaPixel(loader.image(for: url)), try rgbaPixel(loader.image(for: nil)))
  }

  private func rgbaPixel(_ image: UIImage) throws -> [UInt8] {
    let cgImage = try XCTUnwrap(image.cgImage)
    XCTAssertEqual(cgImage.width, 1)
    XCTAssertEqual(cgImage.height, 1)
    var bytes = [UInt8](repeating: 0, count: 4)
    try bytes.withUnsafeMutableBytes { buffer in
      let context = try XCTUnwrap(CGContext(
        data: buffer.baseAddress, width: 1, height: 1,
        bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ))
      context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    return bytes
  }
}
