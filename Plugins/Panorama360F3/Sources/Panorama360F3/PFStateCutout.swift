import CoreGraphics
import Foundation

extension PFState {
  private var lastResultURL: URL? { lastResultPath.map { URL(fileURLWithPath: $0) } }

  /// Why «put back» is off; nil when it is on.
  var putBackReason: PFCutout.PutBackReason? {
    PFCutout.putBackReason(
      memory: doc.lastCutout, lastResult: lastResultURL, imageSize: { PFCutout.pixelSize(of: $0).map { ($0.width, $0.height) } })
  }

  /// The same for the montage, which also needs the panorama the cutout was taken from.
  var putBackInPanoramaReason: PFCutout.PutBackReason? {
    if let reason = putBackReason { return reason }
    guard let path = doc.lastCutout?.resultPathAtExtraction else { return .noPanorama }
    return FileManager.default.fileExists(atPath: path) ? nil : .panoramaMissing
  }

  func putBackText(_ reason: PFCutout.PutBackReason) -> String {
    switch reason {
    case .noCutout: text(.putBackNoCutout)
    case .noPatch: text(.putBackNoPatch)
    case .wrongProportion: text(.putBackWrongProportion)
    case .patchMissing: text(.putBackPatchMissing)
    case .noPanorama: text(.putBackNoPanorama)
    case .panoramaMissing: text(.putBackPanoramaMissing)
    }
  }

  // MARK: extracting

  /// Draws the view as it is now at the cutout size, remembers where it was taken and keeps the picture for the actions.
  @discardableResult
  func extractCutout() throws -> CGImage {
    guard var panorama = resultImage else { throw PFCutoutError.noResult }
    // The viewer's picture is reduced to 4096 px; a wider panorama is read again at its own size, so that the cutout is taken at its real resolution.
    if let path = lastResultPath, let real = PFCutout.pixelSize(of: URL(fileURLWithPath: path)), real.width > panorama.width,
      let full = PFResultLoader.load(URL(fileURLWithPath: path), maxSide: nil)
    {
      panorama = full
    }
    // The camera of the viewer, with the field of view widened so that the sides are multiples of 64 at the real resolution of the panorama.
    var camera = self.camera
    let frame = PFCutout.cutoutFrame(panoramaWidth: panorama.width, fov: camera.fov)
    camera.fov = frame.fov
    let image = try PSRendererFactory.make().renderView(.panorama(panorama), camera: camera, width: frame.width, height: frame.height)
    cutoutImage = image
    mutate {
      $0.lastCutout = PFCutoutMemory(
        yaw: camera.yaw, pitch: camera.pitch, fov: camera.fov, width: frame.width, height: frame.height,
        resultPathAtExtraction: lastResultPath, patchPath: nil)
    }
    return image
  }

  // MARK: the actions

  func writeTemporary(_ image: CGImage, prefix: String) throws -> URL {
    guard let data = PFPixels.pngData(image) else { throw PFCutoutError.cannotWrite }
    try? FileManager.default.createDirectory(at: exchangeFolder, withIntermediateDirectories: true)
    let url = exchangeFolder.appendingPathComponent("\(prefix)-\(UUID().uuidString).png")
    do { try data.write(to: url) } catch { throw PFCutoutError.cannotWrite }
    return url
  }

  func sendCutoutAsStartImage(contribute: PFContribute) async {
    let size = cutoutImage.map { (width: $0.width, height: $0.height) }
    await sendCutout(contribute: contribute) { PFCutoutActions.startImageBody(file: $0, width: size?.width ?? 0, height: size?.height ?? 0) }
  }

  func addCutoutToMoodboard(contribute: PFContribute) async { await sendCutout(contribute: contribute, body: PFCutoutActions.moodboardBody) }

  private func sendCutout(contribute: PFContribute, body: (URL) -> [String: Any]) async {
    error = nil
    guard let image = cutoutImage else {
      error = text(.cutoutNothing)
      return
    }
    do {
      let file = try writeTemporary(image, prefix: "pano-360-f3-cutout")
      error = problem(in: await contribute(body(file)))
    } catch {
      self.error = text(.sendFailed)
    }
  }

  func saveCutout(to url: URL) throws {
    guard let image = cutoutImage else { throw PFCutoutError.nothingExtracted }
    guard let data = PFPixels.pngData(image) else { throw PFCutoutError.cannotWrite }
    do { try data.write(to: url) } catch { throw PFCutoutError.cannotWrite }
  }

  /// The retouched picture is pasted on the panorama the cutout was taken from, with a soft edge, and the montage goes to the Results.
  func putBackInPanorama(contribute: PFContribute) async {
    error = nil
    guard putBackInPanoramaReason == nil, let memory = doc.lastCutout, let patchURL = PFCutout.patch(memory: memory, lastResult: lastResultURL),
      let backgroundPath = memory.resultPathAtExtraction, let background = PFResultLoader.load(URL(fileURLWithPath: backgroundPath), maxSide: nil),
      let patch = PFResultLoader.load(patchURL)
    else {
      error = text(.putBackOff)
      return
    }
    isSending = true
    defer { isSending = false }
    let folder = projectFolder
    do {
      let place = Sticker(name: "patch", file: "", yaw: memory.yaw, pitch: memory.pitch, rot: 0, hfov: memory.fov)
      // The retouch is brought to the pixel density it has in the panorama with a quality resize, so that it is pasted without the stair-steps of a
      // bilinear read squeezed by a factor of two or more.
      let density = PFCutout.patchDensityWidth(panoramaWidth: background.width, fov: memory.fov)
      var pasted = patch
      if patch.width > density {
        let height = max(1, Int((Double(patch.height) * Double(density) / Double(patch.width)).rounded()))
        pasted = PFPixels.scaled(patch, width: density, height: height) ?? patch
      }
      var layer = PSLayer(image: pasted, basis: PSProjection.basis(for: place, aspect: Double(patch.width) / Double(patch.height)), opacity: 1)
      layer.feather = 0.03
      let montage = try PSRendererFactory.make().render([layer], width: background.width, height: background.height, uOffset: 0, background: background)
      let file = try writeTemporary(montage, prefix: "pano-360-f3-montage")
      let description = text(.montageDescription, memory.yaw, memory.pitch, memory.fov)
      if let message = problem(in: await contribute(PFCutoutActions.montageBody(file: file, description: description))) {
        error = message
      } else if projectFolder == folder {
        // Only in the project the montage was made in: the app answered while the user may have opened another one.
        mutate { $0.lastCutout?.patchPath = patchURL.path }
      }
    } catch {
      self.error = text(.sendFailed)
    }
  }
}
