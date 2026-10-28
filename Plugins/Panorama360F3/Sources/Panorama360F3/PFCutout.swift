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
  /// The cutout is always taken at the **real resolution** of the panorama. The view covers 2·tan(fov/2) of the picture plane and the panorama has W/2π pixels
  /// per radian, so W · tan(fov/2) / π pixels fall across the view (and three quarters of that down it). Each side is **extended** to the next multiple of 64
  /// (the Generation tab needs it) and the field of view widens by the same ratio: a little more picture, the same pixels per degree, nothing stretched.
  /// Below 512 × 384 (a narrow view of a small panorama) or above 4096 × 3072 the size is held there and the field of view is the one asked for.
  static func cutoutFrame(panoramaWidth: Int, fov: Double) -> (width: Int, height: Int, fov: Double) {
    let tanHalf = tan(min(160, max(20, fov)) * .pi / 180 / 2)
    let nativeWidth = Double(panoramaWidth) * tanHalf / .pi
    let width = Int((nativeWidth / 64).rounded(.up)) * 64
    let height = Int((nativeWidth * 3 / 4 / 64).rounded(.up)) * 64
    guard width >= 512, width <= 4096, height <= 3072 else {
      return width < 512 ? (512, 384, fov) : (4096, 3072, fov)
    }
    return (width, height, 2 * atan(tanHalf * Double(width) / nativeWidth) * 180 / .pi)
  }

  /// The width, in pixels, that a retouch taken over `fov` degrees has in a panorama `panoramaWidth` wide. A retouch with more pixels than this is brought
  /// to it with a quality resize before it is pasted: the renderer reads the retouch with a plain bilinear filter, which squeezed by a factor of two or more
  /// leaves hard stair-steps on every edge (and the paste looks much worse than the soft panorama around it).
  static func patchDensityWidth(panoramaWidth: Int, fov: Double) -> Int {
    max(1, Int((Double(panoramaWidth) * tan(min(170, max(5, fov)) * .pi / 180 / 2) / .pi).rounded()))
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

  /// The picture as the start image, and the Generation tab's size set to its own real size: the retouch is made at the size of the cutout, so its result has the
  /// same proportion and can be put back.
  static func startImageBody(file: URL, width: Int, height: Int) -> [String: Any] {
    var fields: [String: Any] = ["width": width, "height": height]
    // A side above 2048 is cut by the Generation tab unless HiRes is on.
    if max(width, height) > 2048 { fields["highRes"] = true }
    return ["startImage": ["path": file.path, "name": pictureName], "fields": fields]
  }

  static func moodboardBody(file: URL) -> [String: Any] { ["moodboard": [["path": file.path, "name": pictureName]]] }

  static func montageBody(file: URL, description: String) -> [String: Any] {
    ["result": ["path": file.path, "name": montageName, "description": description]]
  }
}
