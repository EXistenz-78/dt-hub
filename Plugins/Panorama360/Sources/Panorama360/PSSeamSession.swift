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

/// One correction of the seam, as DT Hub drives it (a guided pipeline of one pass): `next` gives the pass (the panorama rolled by half, with a green
/// stripe on the seam), `end` takes what the model made and puts its central band into the panorama. It keeps the panorama it was made with: what happens to the result shown meanwhile does not matter.
final class PSSeamSession: @unchecked Sendable {
  private let plan: PSSeamPlan
  private let folder: URL
  private let italian: Bool
  private let rolled: CGImage?
  /// The description of the place, the prompt of the pass.
  let description: String
  private var passGiven = false
  private var finished = false
  private var writeFailed = false
  private var files: [URL] = []

  init(panorama: CGImage, plan: PSSeamPlan, folder: URL, italian: Bool, description: String) {
    self.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
    self.plan = plan
    self.folder = folder
    self.italian = italian
    rolled = PSSeamImages.rolled(panorama, by: plan.rollColumns)
  }

  /// A pass like the real one, for the meter of computing units: the preset and the size.
  func estimate() -> [String: Any] {
    ["preset": PSSeam.presetName, "size": ["width": plan.width, "height": plan.height]]
  }

  /// The one pass: the whole panorama, rolled by half, with the green stripe over the seam, and the preset (which holds the LoRA and the parameters).
  /// No mask: the model fills the green. The prompt is the description of the place, sent even when empty (the app would keep the tab's).
  func next(index: Int, count: Int) -> [String: Any] {
    guard index == 1, !passGiven, let rolled, let painted = PSSeamImages.paintGreen(rolled, x: plan.greenX, width: plan.greenWidth),
      let picture = PSSeamImages.pngData(painted)
    else { return ["done": true] }
    let pictureURL = folder.appendingPathComponent("seam-panorama.png")
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try picture.write(to: pictureURL)
    } catch {
      writeFailed = true
      return ["done": true]
    }
    files = [pictureURL]
    passGiven = true
    return [
      "title": "Giunzione", "startImage": ["path": pictureURL.path, "name": "seam-panorama"],
      "size": ["width": plan.width, "height": plan.height], "preset": PSSeam.presetName, "strength": PSSeam.strength,
      "fields": ["prompt": description],
    ]
  }

  /// The run is over. With `finished` and the picture the model made (`previous`), the corrected panorama; otherwise nothing, and why.
  func end(reason: String, previous: (path: String, width: Int, height: Int)?) -> PSSeamOutcome {
    defer { for file in files { try? FileManager.default.removeItem(at: file) } }
    guard !finished else { return .nothing(.closed) }
    if writeFailed { return .nothing(.failed) }
    switch reason {
    case "finished": break
    case "stopped": return .nothing(.stopped)
    case "closed": return .nothing(.closed)
    default: return .nothing(.failed)
    }
    guard let previous else { return .nothing(.noPicture) }
    guard previous.width == plan.width, previous.height == plan.height else { return .nothing(.wrongSize) }
    guard let generated = PSResultLoader.load(URL(fileURLWithPath: previous.path), maxSide: nil) else { return .nothing(.unreadable) }
    guard generated.width == plan.width, generated.height == plan.height else { return .nothing(.wrongSize) }
    guard let rolled, let composed = PSSeamImages.compose(rolled: rolled, generated: generated, plan: plan),
      let corrected = PSSeamImages.rolled(composed, by: plan.width - plan.rollColumns)
    else { return .nothing(.failed) }
    finished = true
    return .montage(corrected, description: L.format(.seamDescription, plan.bandWidth, italian: italian))
  }
}
