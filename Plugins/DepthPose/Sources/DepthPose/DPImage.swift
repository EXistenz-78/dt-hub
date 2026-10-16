import CoreGraphics
import Foundation
import ImageIO

/// Opens a picture for the plug-in: the way the user sees it (EXIF orientation applied), at most `maxLongSide` pixels
/// on the long side, always 8-bit RGB (transparency over black, so Vision and the model never see a hole).
enum DPImage {
  static let maxLongSide = 2048

  static func load(data: Data) -> CGImage? {
    guard !data.isEmpty, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return load(source)
  }

  static func load(file: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
    return load(source)
  }

  private static func load(_ source: CGImageSource) -> CGImage? {
    guard CGImageSourceGetCount(source) > 0,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
    else { return nil }
    // The thumbnail call applies the orientation and reads a huge picture straight at the reduced size.
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: min(maxLongSide, max(width, height)),
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return rgb(image)
  }

  /// The picture as 8-bit sRGB without alpha, over black.
  static func rgb(_ image: CGImage) -> CGImage? {
    guard
      let context = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(rect)
    context.interpolationQuality = .high
    context.draw(image, in: rect)
    return context.makeImage()
  }
}
