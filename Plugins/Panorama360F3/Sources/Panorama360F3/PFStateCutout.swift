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
    guard let panorama = resultImage else { throw PFCutoutError.noResult }
    let size = PFCutout.size(megapixels: doc.cutoutMegapixels)
    let camera = self.camera
    let image = try PSRendererFactory.make().renderView(.panorama(panorama), camera: camera, width: size.width, height: size.height)
    cutoutImage = image
    mutate {
      $0.lastCutout = PFCutoutMemory(
        yaw: camera.yaw, pitch: camera.pitch, fov: camera.fov, width: size.width, height: size.height,
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
      var layer = PSLayer(image: patch, basis: PSProjection.basis(for: place, aspect: Double(patch.width) / Double(patch.height)), opacity: 1)
      layer.feather = 0.03
      // The panorama is enlarged so that the retouch keeps its pixels instead of being squeezed to the density of the panorama.
      let target = PFCutout.montageSize(background: (background.width, background.height), patchWidth: patch.width, fov: memory.fov)
      guard let enlarged = PFPixels.scaled(background, width: target.0, height: target.1) else { throw PFCutoutError.cannotWrite }
      let montage = try PSRendererFactory.make().render([layer], width: target.0, height: target.1, uOffset: 0, background: enlarged)
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
