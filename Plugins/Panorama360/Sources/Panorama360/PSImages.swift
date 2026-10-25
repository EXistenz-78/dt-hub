import CoreGraphics
import Foundation
import ImageIO

/// The pictures of the stickers in memory, by sticker id.
@MainActor
final class PSImageCache {
  private var images: [UUID: CGImage] = [:]

  func set(_ image: CGImage, for id: UUID) { images[id] = image }
  func remove(_ id: UUID) { images[id] = nil }
  func removeAll() { images = [:] }

  /// The cached picture, or the one read from `url` (and cached).
  func image(for id: UUID, loading url: URL?) -> CGImage? {
    if let image = images[id] { return image }
    guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    images[id] = image
    return image
  }
}

/// Reads the last result of the project: upright, at most 4096 px on the long side (the plug-in only looks at it).
enum PSResultLoader {
  static let maxSide = 4096

  /// `maxSide` nil keeps the picture's own size (the montage is made at the size of the result it is pasted on).
  static func load(_ url: URL, maxSide: Int? = PSResultLoader.maxSide) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else { return nil }
    var options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    if let maxSide {
      options[kCGImageSourceThumbnailMaxPixelSize] = maxSide
    } else if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int
    {
      options[kCGImageSourceThumbnailMaxPixelSize] = max(width, height)
    }
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary), image.width > 0, image.height > 0
    else { return nil }
    return image
  }
}
