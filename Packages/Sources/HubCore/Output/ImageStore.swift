import CoreGraphics
import Foundation
import HubKit
import ImageIO
import UniformTypeIdentifiers

/// Where generated images are written (spec §7: saved automatically, as PNG with the prompt
/// and the configuration inside).
public protocol ImageStore: Sendable {
  /// Saves one image of a RUN and returns its file. `elapsed` is the time it took to make, in seconds
  /// (nil when unknown); it goes into the file's metadata.
  func save(_ image: CGImage, job: GenerationJob, index: Int, date: Date, elapsed: TimeInterval?) throws -> URL
  /// Moves a saved file to the Trash (a file that is not there any more counts as done).
  func trash(_ url: URL) throws
}

extension ImageStore {
  /// Saves an image whose time is not known.
  public func save(_ image: CGImage, job: GenerationJob, index: Int, date: Date) throws -> URL {
    try save(image, job: job, index: index, date: date, elapsed: nil)
  }

  public func trash(_ url: URL) throws {
    do {
      try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
      return
    } catch {
      throw ImageStoreError.cannotTrash(error.localizedDescription)
    }
  }
}

public enum ImageStoreError: Error, Equatable, Sendable {
  case cannotWrite(String)
  case cannotTrash(String)
}

/// PNG files in `folder/yyyy-MM-dd/HHmmss-<seed>[-<n>].png`. The PNG "Description" holds the
/// prompt; the EXIF "UserComment" holds the whole job as JSON (read back by `job(in:)`), with one more
/// key, `elapsedSeconds`, for the time the image took (read back by `elapsed(in:)`).
/// ImageIO does not write the PNG "Comment" chunk, hence EXIF.
public struct PNGImageStore: ImageStore {
  public let folder: URL
  /// The key of the time in the job's JSON; the job's own decoding ignores it.
  static let elapsedKey = "elapsedSeconds"

  public init(folder: URL) {
    self.folder = folder
  }

  public func save(_ image: CGImage, job: GenerationJob, index: Int, date: Date, elapsed: TimeInterval?) throws -> URL {
    let day = Self.format(date, "yyyy-MM-dd")
    let directory = folder.appendingPathComponent(day, isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      throw ImageStoreError.cannotWrite(error.localizedDescription)
    }
    let base = "\(Self.format(date, "HHmmss"))-\(job.parameters.seed)" + (index > 0 ? "-\(index + 1)" : "")
    let url = Self.unusedURL(in: directory, base: base)

    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw ImageStoreError.cannotWrite(url.path) }
    let json = Self.comment(for: job, elapsed: elapsed)
    let properties: [CFString: Any] = [
      kCGImagePropertyPNGDictionary: [
        kCGImagePropertyPNGDescription: job.promptWithTriggers,
        kCGImagePropertyPNGSoftware: "DT Hub",
      ],
      kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: json],
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw ImageStoreError.cannotWrite(url.path) }
    return url
  }

  /// A saved picture decoded with its longest side at most `maxPixel` (the strip of the Results
  /// window keeps small ones; the chosen image is loaded larger).
  public static func image(at url: URL, maxPixel: Int) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: max(maxPixel, 1),
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  /// The job saved inside a PNG written by this store, or nil.
  public static func job(in url: URL) -> GenerationJob? {
    guard let json = comment(in: url) else { return nil }
    return try? JSONDecoder().decode(GenerationJob.self, from: Data(json.utf8))
  }

  /// The seconds the image took, saved inside a PNG written by this store; nil for a file from before
  /// the time was kept.
  public static func elapsed(in url: URL) -> TimeInterval? {
    guard let json = comment(in: url),
      let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    else { return nil }
    return object[elapsedKey] as? Double
  }

  /// The job as JSON, with the time when it is known.
  private static func comment(for job: GenerationJob, elapsed: TimeInterval?) -> String {
    guard let data = try? JSONEncoder().encode(job) else { return "" }
    if let elapsed, var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      object[elapsedKey] = elapsed
      if let withTime = try? JSONSerialization.data(withJSONObject: object) {
        return String(data: withTime, encoding: .utf8) ?? ""
      }
    }
    return String(data: data, encoding: .utf8) ?? ""
  }

  private static func comment(in url: URL) -> String? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
    else { return nil }
    return exif[kCGImagePropertyExifUserComment] as? String
  }

  private static func unusedURL(in directory: URL, base: String) -> URL {
    var url = directory.appendingPathComponent("\(base).png")
    var counter = 2
    while FileManager.default.fileExists(atPath: url.path) {
      url = directory.appendingPathComponent("\(base)_\(counter).png")
      counter += 1
    }
    return url
  }

  private static func format(_ date: Date, _ pattern: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = pattern
    return formatter.string(from: date)
  }
}
