import CoreGraphics
import Foundation
import ImageIO

/// Why nothing was made of a pipeline that ended.
enum PFProblem: Equatable {
  case stopped
  case failed
  case closed
  /// The run finished but the app did not send the picture it made.
  case noPicture
  /// The picture the Seamfix pass made is not the size of the pass.
  case wrongSize
  case unreadable
}

enum PFOutcome {
  /// A panorama for the Results: with the seam corrected, or the raw one of the first pass (the correction could not be made).
  case panorama(CGImage, corrected: Bool)
  case nothing(PFProblem)
}

/// One run of the guided pipeline, as DT Hub drives it. `generate` has two passes (the panorama from the Moodboard pictures, then the Seamfix pass on the
/// square made from it); `seamOnly` has the Seamfix pass alone, on a panorama the plug-in already has. `next` gives the pass asked for, `end` takes what
/// the model made and puts it back. The files it writes in `folder` are deleted by `end`.
final class PFSession: @unchecked Sendable {
  enum Kind {
    case generate(images: [URL], description: String, size: PFSize)
    case seamOnly(panorama: CGImage)
  }

  typealias Previous = (path: String, width: Int, height: Int)

  private let kind: Kind
  private let folder: URL
  /// The panorama the square is made from and the result is put back into (the one of pass 1, or the given one).
  private var panorama: CGImage?
  private var plan: PFSeamPlan?
  private var given = 0
  private var finished = false
  private var files: [URL] = []

  init(kind: Kind, folder: URL) {
    self.kind = kind
    self.folder = folder
    if case .seamOnly(let image) = kind {
      panorama = image
      if case .success(let found) = PFSeam.plan(width: image.width, height: image.height) { plan = found }
    }
  }

  var passCount: Int {
    switch kind {
    case .generate: 2
    case .seamOnly: 1
    }
  }

  /// A pass like the real one, for the meter of computing units: the preset and the size.
  func estimate() -> [String: Any] {
    switch kind {
    case .generate(_, _, let size): ["preset": PFPresets.panoName, "size": ["width": size.width, "height": size.height]]
    case .seamOnly(let image):
      ["preset": PFPresets.seamName, "size": ["width": plan?.side ?? image.height, "height": plan?.side ?? image.height]]
    }
  }

  /// The pass asked for, or `{"done":true}` when it is not the next one in order, cannot be made, or there is none.
  func next(index: Int, previous: Previous?) -> [String: Any] {
    let done: [String: Any] = ["done": true]
    guard !finished, index == given + 1 else { return done }
    switch kind {
    case .generate(let images, let description, let size):
      if index == 1 {
        guard let pass = firstPass(images: images, description: description, size: size) else { return done }
        given = 1
        return pass
      }
      guard index == 2, let previous, let picture = Self.load(URL(fileURLWithPath: previous.path)),
        case .success(let found) = PFSeam.plan(width: picture.width, height: picture.height), let pass = seamPass(panorama: picture, plan: found)
      else { return done }
      panorama = picture
      plan = found
      given = 2
      return pass
    case .seamOnly:
      guard index == 1, let panorama, let plan, let pass = seamPass(panorama: panorama, plan: plan) else { return done }
      given = 1
      return pass
    }
  }

  /// The run is over. With `finished` and the picture the Seamfix pass made (`previous`), the corrected panorama; otherwise, once pass 1 is done, the raw
  /// panorama of pass 1 (a `generate` run) so the work is not lost; otherwise nothing, and why.
  func end(reason: String, previous: Previous?) -> PFOutcome {
    defer { for file in files { try? FileManager.default.removeItem(at: file) } }
    guard !finished else { return .nothing(.closed) }
    finished = true
    let why: PFProblem
    switch reason {
    case "finished": why = .noPicture
    case "stopped": why = .stopped
    case "closed": why = .closed
    default: why = .failed
    }
    if reason == "finished", let outcome = merged(previous: previous) { return outcome }
    // Not corrected: the raw panorama of a `generate` run, if there is one.
    if case .generate(_, _, let size) = kind {
      if let panorama { return .panorama(panorama, corrected: false) }
      // The run stopped between the two passes: the app still holds the picture of pass 1.
      if given == 1, let previous, previous.width == size.width, previous.height == size.height,
        let picture = Self.load(URL(fileURLWithPath: previous.path))
      {
        return .panorama(picture, corrected: false)
      }
    }
    return .nothing(reason == "finished" ? failure(previous: previous) : why)
  }

  // MARK: passes

  private func firstPass(images: [URL], description: String, size: PFSize) -> [String: Any]? {
    guard !images.isEmpty else { return nil }
    var moodboard: [[String: Any]] = []
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      for (index, url) in images.enumerated() {
        let copy = folder.appendingPathComponent("reference-\(index + 1)-\(UUID().uuidString).\(url.pathExtension)")
        try FileManager.default.copyItem(at: url, to: copy)
        files.append(copy)
        moodboard.append(["path": copy.path, "name": url.lastPathComponent])
      }
    } catch {
      return nil
    }
    return [
      "title": "Panorama", "preset": PFPresets.panoName, "moodboard": moodboard, "size": ["width": size.width, "height": size.height],
      "fields": ["prompt": PFPrompt.panorama(imageCount: images.count, description: description), "highRes": true, "randomSeed": true] as [String: Any],
      "loras": [PFPresets.lora(seam: false)],
    ]
  }

  /// The Seamfix pass: the square with the white bar as the start image, no Moodboard, an empty prompt (DT Hub adds the trigger word).
  private func seamPass(panorama: CGImage, plan: PFSeamPlan) -> [String: Any]? {
    guard let square = PFSeam.square(from: panorama, plan: plan, withBar: true), let data = PFPixels.pngData(square) else { return nil }
    let url = folder.appendingPathComponent("seam-square-\(UUID().uuidString).png")
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try data.write(to: url)
    } catch {
      return nil
    }
    files.append(url)
    return [
      "title": "Giunzione", "preset": PFPresets.seamName, "startImage": ["path": url.path, "name": "seam-square"],
      "size": ["width": plan.side, "height": plan.side], "strength": 1.0,
      "fields": ["prompt": "", "highRes": true, "randomSeed": true] as [String: Any],
      "loras": [PFPresets.lora(seam: true)],
    ]
  }

  // MARK: end

  /// The corrected panorama when the picture of the Seamfix pass is there, the right size and readable.
  private func merged(previous: Previous?) -> PFOutcome? {
    // The pass is run at exactly its size; a square picture of another size is scaled to it (spec §6), anything else cannot be used.
    guard let previous, let panorama, let plan, previous.width == previous.height,
      let generated = Self.load(URL(fileURLWithPath: previous.path)), generated.width == generated.height,
      let square = Self.scaled(generated, toSide: plan.side), let image = PFSeam.merge(result: square, into: panorama, plan: plan)
    else { return nil }
    return .panorama(image, corrected: true)
  }

  /// Why a `finished` run could not be corrected (for `seamOnly`, which has no raw panorama to fall back on).
  private func failure(previous: Previous?) -> PFProblem {
    guard let previous else { return .noPicture }
    guard previous.width == previous.height else { return .wrongSize }
    return Self.load(URL(fileURLWithPath: previous.path)) == nil ? .unreadable : .failed
  }

  /// The picture at `side × side` (high-quality interpolation); the picture itself when it already is that size.
  static func scaled(_ image: CGImage, toSide side: Int) -> CGImage? {
    guard image.width != side || image.height != side else { return image }
    guard let context = CGContext(
      data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    return context.makeImage()
  }

  static func load(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }
}
