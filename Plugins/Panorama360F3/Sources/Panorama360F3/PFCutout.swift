import CoreGraphics
import Foundation
import ImageIO

enum PFCutoutError: Error, Equatable {
  /// There is no panorama shown to take a view from.
  case noResult
  case nothingExtracted
  case cannotWrite
}

/// Where a cutout was taken and which retouch was already put back. Adapted from Panorama 360's `PSCutoutMemory`.
struct PFCutoutMemory: Codable, Equatable, Sendable {
  var yaw: Double
  var pitch: Double
  var fov: Double
  var width: Int
  var height: Int
  /// The result that was shown when the cutout was taken; a retouch is a result that differs from it.
  var resultPathAtExtraction: String?
  /// The retouched picture already put back once: the button keeps working on it after the montage became the newest result.
  var patchPath: String?
}

/// The cutout: the view seen from the camera, taken as a flat 4:3 picture, and the rules for putting a retouched version back (as in Panorama 360).
enum PFCutout {
  static let megapixelRange = 0.25...4.0

  /// The picture's size: exactly 4:3, like the view it is taken from, with both sides multiples of 64. A width that is a multiple of 256 gives a height
  /// that is a multiple of 192, so 1.0 MP → 1280 × 960 (0.25 MP → 512 × 384, 4 MP → 2304 × 1728).
  static func size(megapixels: Double) -> (width: Int, height: Int) {
    let mp = min(megapixelRange.upperBound, max(megapixelRange.lowerBound, megapixels))
    let width = max(2, Int((mp * 1_000_000 * 4 / 3).squareRoot() / 256 + 0.5)) * 256
    return (width, width * 3 / 4)
  }

  /// The widest montage that is made (the limit of a Fix-the-seam pass and of HiRes: 8192 × 4096).
  static let maxMontageWidth = 8192

  /// The size the montage is made at. Put back at the pixel density of the panorama, a retouch of `patchWidth` pixels over `fov` degrees would be
  /// squeezed into `W · fov / 360` pixels and lose its detail; so the panorama is enlarged until the retouch has its own pixels at the centre of the
  /// view (a width of π · patchWidth / tan(fov / 2), rounded up to a multiple of 128), never smaller than it is and never above `maxMontageWidth`
  /// (a panorama already wider keeps its size). The proportions of the panorama are kept.
  static func montageSize(background: (Int, Int), patchWidth: Int, fov: Double) -> (Int, Int) {
    let half = tan(min(170, max(5, fov)) * .pi / 180 / 2)
    let needed = Double(patchWidth) * .pi / half
    var width = background.0
    if needed > Double(width) { width = min(maxMontageWidth, Int((needed / 128).rounded(.up)) * 128) }
    width = max(width, background.0)
    let factor = Double(width) / Double(background.0)
    return (width, Int((Double(background.1) * factor).rounded()))
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
    /// There was no result to compose a montage on when the cutout was taken.
    case noPanorama
    /// The panorama the cutout was taken from has been deleted or moved since.
    case panoramaMissing
  }

  /// The picture to put back: the retouch already used once, otherwise the newest result when it is not the one the cutout was taken from.
  static func patch(memory: PFCutoutMemory?, lastResult: URL?) -> URL? {
    guard let memory else { return nil }
    if let used = memory.patchPath { return URL(fileURLWithPath: used) }
    guard let lastResult, lastResult.path != memory.resultPathAtExtraction else { return nil }
    return lastResult
  }

  static func putBackReason(memory: PFCutoutMemory?, lastResult: URL?, imageSize: (URL) -> (Int, Int)?) -> PutBackReason? {
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
enum PFCutoutActions {
  static let pictureName = "pano-360-f3-cutout.png"
  static let montageName = "pano-360-f3-montage.png"

  /// The picture as the start image, and the Generation tab's size set to its own: the retouch is made at the size of the cutout, so its result has the
  /// same proportion and can be put back.
  static func startImageBody(file: URL, width: Int, height: Int) -> [String: Any] {
    ["startImage": ["path": file.path, "name": pictureName], "fields": ["width": width, "height": height]]
  }

  static func moodboardBody(file: URL) -> [String: Any] { ["moodboard": [["path": file.path, "name": pictureName]]] }

  static func montageBody(file: URL, description: String) -> [String: Any] {
    ["result": ["path": file.path, "name": montageName, "description": description]]
  }
}
