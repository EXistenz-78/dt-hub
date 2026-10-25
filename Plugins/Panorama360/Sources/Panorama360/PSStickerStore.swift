import CoreGraphics
import Foundation
import ImageIO

enum PSStickerError: Error, Equatable {
  case unreadable(String)
  case cannotWrite(String)
}

struct PSStickerAdded: Equatable {
  /// Relative to the project folder.
  var file: String
  /// The picture's size after the EXIF orientation and the reduction.
  var size: CGSize
  /// The field of view the photo's focal length gives; nil without a usable focal length or for a cropped photo.
  var suggestedHFOV: Double?
  /// The photo has a focal length but its proportions are not those the EXIF records: it was cropped, so the focal length is no guide.
  var looksCropped: Bool
}

/// Brings a picture into a project: upright (EXIF orientation applied), at most 2048 px on the long side, as a PNG in the project's
/// `stickers/` folder.
enum PSStickerStore {
  static let maxSide = 2048
  static let folderName = "stickers"

  static func add(contentsOf url: URL, into project: URL) throws -> PSStickerAdded {
    let name = url.lastPathComponent
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
      throw PSStickerError.unreadable(name)
    }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxSide, kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary), image.width > 0, image.height > 0 else {
      throw PSStickerError.unreadable(name)
    }
    let folder = project.appendingPathComponent(folderName, isDirectory: true)
    let file = "\(folderName)/\(UUID().uuidString).png"
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      guard let destination = CGImageDestinationCreateWithURL(project.appendingPathComponent(file) as CFURL, "public.png" as CFString, 1, nil)
      else { throw PSStickerError.cannotWrite(name) }
      CGImageDestinationAddImage(destination, image, nil)
      guard CGImageDestinationFinalize(destination) else { throw PSStickerError.cannotWrite(name) }
    } catch let error as PSStickerError {
      throw error
    } catch {
      throw PSStickerError.cannotWrite(name)
    }
    let focal = focalLength35mm(of: source)
    let size = CGSize(width: image.width, height: image.height)
    let cropped = focal != nil && recordedDimensions(of: source).map { isCropped(recordedWidth: $0.width, recordedHeight: $0.height, size: size) } == true
    let fov = focal.flatMap { cropped ? nil : PSProjection.horizontalFOV(focal35mm: $0, aspect: size.width / size.height) }
    return PSStickerAdded(file: file, size: size, suggestedHFOV: fov, looksCropped: cropped)
  }

  private static func exif(of source: CGImageSource) -> [CFString: Any]? {
    (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])?[kCGImagePropertyExifDictionary] as? [CFString: Any]
  }

  /// The 35 mm equivalent focal length, which already holds the crop factor of the sensor; nil when it is missing or 0.
  private static func focalLength35mm(of source: CGImageSource) -> Double? {
    guard let value = exif(of: source)?[kCGImagePropertyExifFocalLenIn35mmFilm] as? NSNumber, value.doubleValue > 0 else { return nil }
    return value.doubleValue
  }

  /// The pixel dimensions the EXIF records (those of the shot, before any crop).
  private static func recordedDimensions(of source: CGImageSource) -> (width: Double, height: Double)? {
    guard let dictionary = exif(of: source), let x = (dictionary[kCGImagePropertyExifPixelXDimension] as? NSNumber)?.doubleValue,
      let y = (dictionary[kCGImagePropertyExifPixelYDimension] as? NSNumber)?.doubleValue, x > 0, y > 0
    else { return nil }
    return (x, y)
  }

  /// True when the proportions of the picture (whatever its orientation) differ by more than 2 % from the recorded ones.
  static func isCropped(recordedWidth: Double, recordedHeight: Double, size: CGSize) -> Bool {
    let recorded = max(recordedWidth, recordedHeight) / min(recordedWidth, recordedHeight)
    let actual = max(size.width, size.height) / min(size.width, size.height)
    return abs(actual - recorded) / recorded > 0.02
  }
}
