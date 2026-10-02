import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Why an image could not be taken into the Control tab.
public enum ControlError: Error, Equatable, Sendable {
  /// The file is not an image the system can read; the detail is its name.
  case unreadable(String)
  /// The copy could not be written (disk full, folder not writable); the detail says why.
  case cannotSave(String)
}

/// A copy that was just written.
public struct StoredPicture: Equatable, Sendable {
  public let fileName: String
  public let pixelWidth: Int
  public let pixelHeight: Int
}

/// Where the copies of the Control tab's images live (tab Control spec §4). The real one is a
/// folder; tests may use another.
public protocol ReferenceStorage: Sendable {
  /// Reads the picture's size (orientation applied) and writes a copy of the bytes as they are.
  func save(_ data: Data, name: String) throws(ControlError) -> StoredPicture
  /// The picture decoded with its longest side at most `maxPixel`, orientation applied.
  func image(named fileName: String, maxPixel: Int) -> CGImage?
  func exists(_ fileName: String) -> Bool
  func remove(_ fileName: String)
  func allFileNames() -> [String]
}

/// Copies in `~/Library/Application Support/DT Hub/Control/`.
public struct FileReferenceStorage: ReferenceStorage {
  public let folder: URL

  public init(folder: URL) {
    self.folder = folder
  }

  public static var defaultFolder: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true)
      .appendingPathComponent("Control", isDirectory: true)
  }

  public func save(_ data: Data, name: String) throws(ControlError) -> StoredPicture {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
    else { throw .unreadable(name) }
    // A file with a readable header and a damaged body is refused now, not at RUN: the picture
    // must be complete and decode (a small version is enough to know).
    let probe: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 64,
    ]
    guard CGImageSourceCreateThumbnailAtIndex(source, 0, probe as CFDictionary) != nil
    else { throw .unreadable(name) }
    // ImageIO decodes a truncated picture as far as it goes and calls it done; a PNG that lost
    // its end (a cut download) is told by the missing IEND chunk. Other formats are not checked.
    if CGImageSourceGetType(source) as String? == UTType.png.identifier, data.range(of: Data("IEND".utf8)) == nil {
      throw .unreadable(name)
    }
    // EXIF orientations 5…8 turn the picture on its side: the size shown is the turned one.
    let turned = (5...8).contains(properties[kCGImagePropertyOrientation] as? Int ?? 1)
    let type = CGImageSourceGetType(source).flatMap { UTType($0 as String) }
    let fileName = "\(UUID().uuidString).\(type?.preferredFilenameExtension ?? "img")"
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try data.write(to: folder.appendingPathComponent(fileName), options: .atomic)
    } catch {
      throw .cannotSave(error.localizedDescription)
    }
    return StoredPicture(fileName: fileName, pixelWidth: turned ? height : width, pixelHeight: turned ? width : height)
  }

  public func image(named fileName: String, maxPixel: Int) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(folder.appendingPathComponent(fileName) as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: max(maxPixel, 1),
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  public func exists(_ fileName: String) -> Bool {
    FileManager.default.fileExists(atPath: folder.appendingPathComponent(fileName).path)
  }

  public func remove(_ fileName: String) {
    try? FileManager.default.removeItem(at: folder.appendingPathComponent(fileName))
  }

  public func allFileNames() -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
  }
}
