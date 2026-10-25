import CoreGraphics
import Foundation
import ImageIO

/// What «Send to Generation» tells the app: one `contribute` that names the saved preset (its steps, guidance, sampler, LoRA with its trigger
/// phrase, model and refiner come from it) and gives the ERP as the start image. The prompt is only the description of the place.
enum PSSender {
  static let width = 2048
  static let height = 1024
  static let startImageName = "panorama-360.png"

  static func body(startImage: URL, description: String, mode: PanoMode) -> [String: Any] {
    // The prompt is always sent, empty too: the preset has none, and the app would keep whatever the Generation tab held before.
    let fields: [String: Any] = ["width": width, "height": height, "prompt": description.trimmingCharacters(in: .whitespacesAndNewlines)]
    return [
      "preset": mode == .fast ? PSPresets.fastName : PSPresets.normalName,
      "startImage": ["path": startImage.path, "name": startImageName],
      "fields": fields,
      "strength": 1.0,
    ]
  }

  static func writePNG(_ image: CGImage, to url: URL) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
  }
}

extension PSState {
  /// The text of the box under the prompt for a model that is not a Base one: shown only once something has been sent (the preset changes the model).
  var warning: String? { hasSent && modelIsBase == false ? text(.notBaseWarning) : nil }

  /// Draws the ERP, writes it in the folder the app gave, and sends one `contribute`. What the app answers in `problems`, or an error, goes in `error`.
  func send(contribute: PSContribute) async {
    error = nil
    hasSent = false
    guard projectFolder != nil else {
      error = text(.openProjectFirst)
      return
    }
    guard doc.stickers.contains(where: \.visible) else {
      error = text(.noVisibleSticker)
      return
    }
    isSending = true
    defer { isSending = false }
    let folder = URL(fileURLWithPath: tempFolder.isEmpty ? NSTemporaryDirectory() : tempFolder, isDirectory: true)
    let file = folder.appendingPathComponent("panorama-360-\(UUID().uuidString).png")
    do {
      let image = try renderedERP(width: PSSender.width, height: PSSender.height)
      try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      guard PSSender.writePNG(image, to: file) else {
        error = text(.sendFailed)
        return
      }
    } catch {
      self.error = text(.sendFailed)
      return
    }
    guard let answer = await contribute(PSSender.body(startImage: file, description: doc.description, mode: doc.mode)) else {
      error = text(.noAnswerFromApp)
      return
    }
    if answer["type"] as? String == "error" {
      error = answer["text"] as? String ?? text(.noAnswerFromApp)
    } else if let problems = answer["problems"] as? [String], !problems.isEmpty {
      error = problems.joined(separator: "\n")
    } else {
      hasSent = true
    }
  }
}
