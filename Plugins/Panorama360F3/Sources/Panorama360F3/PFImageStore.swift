import CoreGraphics
import Foundation
import ImageIO

enum PFImageError: Error, Equatable {
  case unreadable(String)
  case cannotWrite(String)
}

/// Brings a picture into a project: upright (EXIF orientation applied), at most 2048 px on the long side, as a PNG in the project's `images/` folder.
enum PFImageStore {
  static let maxSide = 2048
  static let folderName = "images"

  static func add(contentsOf url: URL, into project: URL) throws -> PFImage {
    let name = url.lastPathComponent
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
      throw PFImageError.unreadable(name)
    }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxSide, kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary), image.width > 0, image.height > 0 else {
      throw PFImageError.unreadable(name)
    }
    let folder = project.appendingPathComponent(folderName, isDirectory: true)
    let file = "\(folderName)/\(UUID().uuidString).png"
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      guard let destination = CGImageDestinationCreateWithURL(project.appendingPathComponent(file) as CFURL, "public.png" as CFString, 1, nil)
      else { throw PFImageError.cannotWrite(name) }
      CGImageDestinationAddImage(destination, image, nil)
      guard CGImageDestinationFinalize(destination) else { throw PFImageError.cannotWrite(name) }
    } catch let error as PFImageError {
      throw error
    } catch {
      throw PFImageError.cannotWrite(name)
    }
    return PFImage(name: name, file: file)
  }
}
