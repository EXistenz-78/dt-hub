import CoreGraphics
import Foundation
import ImageIO

enum PSCutoutError: Error, Equatable {
  case nothingExtracted
  case cannotWrite
}

/// The cutout: the view seen from the camera, taken as a flat 4:3 picture, and the rules for putting a retouched version back.
enum PSCutout {
  static let megapixelRange = 0.25...4.0

  /// The picture's size: 4:3, the width rounded to a multiple of 64 and the height too (1.0 MP → 1152 × 896).
  static func size(megapixels: Double) -> (width: Int, height: Int) {
    let mp = min(megapixelRange.upperBound, max(megapixelRange.lowerBound, megapixels))
    let width = Int((mp * 1_000_000 * 4 / 3).squareRoot() / 64 + 0.5) * 64
    let height = Int(Double(width) * 3 / 4 / 64 + 0.5) * 64
    return (width, height)
  }

  /// Why «put back» is off; nil when it is on.
  enum PutBackReason: Equatable {
    /// Nothing has been extracted yet.
    case noCutout
    /// There is no retouch yet: the newest result is still the one the cutout was taken from.
    case noPatch
    /// The retouch does not have the proportion of the cutout.
    case wrongProportion
    /// The file of the retouch cannot be read.
    case patchMissing
    /// There was no result to compose a montage on when the cutout was taken (only «put back in the panorama»).
    case noPanorama
  }

  /// The picture to put back: the retouch already used once (so both buttons keep working on it after the montage became the newest result),
  /// otherwise the newest result when it is not the one the cutout was taken from.
  static func patch(memory: PSCutoutMemory?, lastResult: URL?) -> URL? {
    guard let memory else { return nil }
    if let used = memory.patchPath { return URL(fileURLWithPath: used) }
    guard let lastResult, lastResult.path != memory.resultPathAtExtraction else { return nil }
    return lastResult
  }

  static func putBackReason(memory: PSCutoutMemory?, lastResult: URL?, imageSize: (URL) -> (Int, Int)?) -> PutBackReason? {
    guard let memory else { return .noCutout }
    guard let patch = patch(memory: memory, lastResult: lastResult) else { return .noPatch }
    guard let size = imageSize(patch), size.0 > 0, size.1 > 0 else { return .patchMissing }
    let wanted = Double(memory.width) / Double(memory.height)
    return abs(Double(size.0) / Double(size.1) - wanted) / wanted > 0.02 ? .wrongProportion : nil
  }

  /// The size of a picture file without decoding it.
  static func pixelSize(of url: URL) -> (width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int
    else { return nil }
    return (width, height)
  }
}

/// What the Cutout sends the app.
enum PSCutoutActions {
  static let pictureName = "panorama-360-cutout.png"
  static let montageName = "panorama-360-montage.png"

  static func startImageBody(file: URL) -> [String: Any] { ["startImage": ["path": file.path, "name": pictureName]] }

  static func moodboardBody(file: URL) -> [String: Any] { ["moodboard": [["path": file.path, "name": pictureName]]] }

  static func montageBody(file: URL, description: String) -> [String: Any] {
    ["result": ["path": file.path, "name": montageName, "description": description]]
  }
}
