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
