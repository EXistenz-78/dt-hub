import CoreGraphics
import Foundation

/// Why nothing was made of a pass that ended.
enum PSSeamProblem: Equatable {
  case stopped
  case failed
  case closed
  /// The run finished but the app did not send the picture it made.
  case noPicture
  /// The picture the model made is not the size of the pass.
  case wrongSize
  case unreadable
}

enum PSSeamOutcome {
  /// The corrected panorama, and the words that go with it in the Results.
  case montage(CGImage, description: String)
  case nothing(PSSeamProblem)
}

/// One correction of the seam, as DT Hub drives it (a guided pipeline of one pass): `next` gives the pass, `end` takes what the model made and puts
/// it into the panorama. It keeps the panorama it was made with: what happens to the result shown meanwhile does not matter.
final class PSSeamSession: @unchecked Sendable {
  private let plan: PSSeamPlan
  private let folder: URL
  private let italian: Bool
  private let rolled: CGImage?
  private var passGiven = false
  private var finished = false

  init(panorama: CGImage, plan: PSSeamPlan, folder: URL, italian: Bool) {
    self.plan = plan
    self.folder = folder
    self.italian = italian
    rolled = PSSeamImages.rolled(panorama, by: plan.rollColumns)
  }

  /// A pass like the real one, for the meter of computing units: the preset and the size.
  func estimate() -> [String: Any] {
    ["preset": PSSeam.presetName, "size": ["width": plan.square, "height": plan.square]]
  }

  /// The one pass: the central square of the rolled panorama and its mask, with the preset (which holds the prompt and the parameters), no fields.
  func next(index: Int, count: Int) -> [String: Any] {
    guard index == 1, !passGiven, let rolled, let square = PSSeamImages.crop(rolled, x: plan.cropX, width: plan.square),
      let picture = PSSeamImages.pngData(square), let mask = PSSeamImages.maskPNG(square: plan.square, bandWidth: plan.bandWidth)
    else { return ["done": true] }
    let pictureURL = folder.appendingPathComponent("seam-square.png")
    let maskURL = folder.appendingPathComponent("seam-mask.png")
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try picture.write(to: pictureURL)
      try mask.write(to: maskURL)
    } catch {
      return ["done": true]
    }
    passGiven = true
    return [
      "title": "Giunzione", "startImage": ["path": pictureURL.path, "name": "seam-square"], "mask": ["path": maskURL.path, "name": "seam-mask"],
      "maskSettings": ["blur": PSSeam.maskBlur, "outset": PSSeam.maskOutset, "preserveOriginal": true],
      "size": ["width": plan.square, "height": plan.square], "preset": PSSeam.presetName, "strength": PSSeam.strength,
    ]
  }

  /// The run is over. With `finished` and the picture the model made (`previous`), the corrected panorama; otherwise nothing, and why.
  func end(reason: String, previous: (path: String, width: Int, height: Int)?) -> PSSeamOutcome {
    guard !finished else { return .nothing(.closed) }
    switch reason {
    case "finished": break
    case "stopped": return .nothing(.stopped)
    case "closed": return .nothing(.closed)
    default: return .nothing(.failed)
    }
    guard let previous else { return .nothing(.noPicture) }
    guard previous.width == plan.square, previous.height == plan.square else { return .nothing(.wrongSize) }
    guard let generated = PSResultLoader.load(URL(fileURLWithPath: previous.path), maxSide: nil) else { return .nothing(.unreadable) }
    guard generated.width == plan.square, generated.height == plan.square else { return .nothing(.wrongSize) }
    guard let rolled, let composed = PSSeamImages.compose(rolled: rolled, generated: generated, plan: plan),
      let corrected = PSSeamImages.rolled(composed, by: plan.width - plan.rollColumns)
    else { return .nothing(.failed) }
    finished = true
    return .montage(corrected, description: L.format(.seamDescription, plan.bandWidth, italian: italian))
  }
}
