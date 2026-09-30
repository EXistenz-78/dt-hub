import CoreGraphics
import Foundation
import HubKit
import ImageIO
import UniformTypeIdentifiers

/// Where generated images are written (spec §7: saved automatically, as PNG with the prompt
/// and the configuration inside).
public protocol ImageStore: Sendable {
  /// Saves one image of a RUN and returns its file.
  func save(_ image: CGImage, job: GenerationJob, index: Int, date: Date) throws -> URL
}

public enum ImageStoreError: Error, Equatable, Sendable {
  case cannotWrite(String)
}

/// PNG files in `folder/yyyy-MM-dd/HHmmss-<seed>[-<n>].png`. The PNG "Description" holds the
/// prompt; the EXIF "UserComment" holds the whole job as JSON (read back by `job(in:)`).
/// ImageIO does not write the PNG "Comment" chunk, hence EXIF.
public struct PNGImageStore: ImageStore {
  public let folder: URL

  public init(folder: URL) {
    self.folder = folder
  }

  public func save(_ image: CGImage, job: GenerationJob, index: Int, date: Date) throws -> URL {
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
    let json = (try? JSONEncoder().encode(job)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    let properties: [CFString: Any] = [
      kCGImagePropertyPNGDictionary: [
        kCGImagePropertyPNGDescription: job.prompt,
        kCGImagePropertyPNGSoftware: "DT Hub",
      ],
      kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: json],
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw ImageStoreError.cannotWrite(url.path) }
    return url
  }

  /// The job saved inside a PNG written by this store, or nil.
  public static func job(in url: URL) -> GenerationJob? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
      let json = exif[kCGImagePropertyExifUserComment] as? String
    else { return nil }
    return try? JSONDecoder().decode(GenerationJob.self, from: Data(json.utf8))
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
