import CoreGraphics
import Foundation
import HubCore

/// The small pictures of the Explore grid: read from the files off the main thread, kept in memory while there is room.
nonisolated final class GalleryThumbnails: @unchecked Sendable {
  static let shared = GalleryThumbnails()

  /// A thumbnail and whether the file is the poster of a video.
  nonisolated final class Thumbnail: @unchecked Sendable {
    let image: CGImage
    let isVideo: Bool
    init(image: CGImage, isVideo: Bool) {
      self.image = image
      self.isVideo = isVideo
    }
    var cost: Int { image.bytesPerRow * image.height }
  }

  private let cache = NSCache<NSString, Thumbnail>()

  private init() {
    cache.totalCostLimit = 200 * 1024 * 1024
  }

  func thumbnail(for url: URL, maxPixel: Int) async -> Thumbnail? {
    let key = "\(url.path)#\(maxPixel)" as NSString
    if let hit = cache.object(forKey: key) { return hit }
    let made = await Task.detached(priority: .utility) { () -> Thumbnail? in
      guard let image = PNGImageStore.image(at: url, maxPixel: maxPixel) else { return nil }
      let video = FileManager.default.fileExists(atPath: PNGImageStore.videoURL(forPoster: url).path)
      return Thumbnail(image: image, isVideo: video)
    }.value
    if let made { cache.setObject(made, forKey: key, cost: made.cost) }
    return made
  }
}
