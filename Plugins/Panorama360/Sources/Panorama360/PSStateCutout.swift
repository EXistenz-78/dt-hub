import CoreGraphics
import Foundation

extension PSState {
  // MARK: Reading

  /// What the view shows, as a source for the renderer.
  func viewSource() -> PSViewSource {
    effectiveSource == .result ? .panorama(resultImage!) : .layers(layers())
  }

  private var lastResultURL: URL? { lastResultPath.map { URL(fileURLWithPath: $0) } }

  /// Why the two «put back» buttons are off; nil when they are on.
  var putBackReason: PSCutout.PutBackReason? {
    PSCutout.putBackReason(
      memory: doc.lastCutout, lastResult: lastResultURL, imageSize: { PSCutout.pixelSize(of: $0).map { ($0.width, $0.height) } })
  }

  /// The same for the montage, which also needs the panorama the cutout was taken from.
  var putBackInPanoramaReason: PSCutout.PutBackReason? {
    if let reason = putBackReason { return reason }
    guard let path = doc.lastCutout?.resultPathAtExtraction else { return .noPanorama }
    return FileManager.default.fileExists(atPath: path) ? nil : .panoramaMissing
  }

  // MARK: Extracting

  /// Draws the view as it is now at the cutout size, remembers where it was taken and keeps the picture for the actions.
  @discardableResult
  func extractCutout() throws -> CGImage {
    let size = PSCutout.size(megapixels: doc.cutoutMegapixels)
    let camera = doc.camera
    let image = try PSRendererFactory.make().renderView(viewSource(), camera: camera, width: size.width, height: size.height)
    cutoutImage = image
    mutate {
      $0.lastCutout = PSCutoutMemory(
        yaw: camera.yaw, pitch: camera.pitch, fov: camera.fov, width: size.width, height: size.height,
        resultPathAtExtraction: lastResultPath, patchPath: nil)
    }
    return image
  }

  // MARK: The actions

  private var exchangeFolder: URL {
    URL(fileURLWithPath: tempFolder.isEmpty ? NSTemporaryDirectory() : tempFolder, isDirectory: true)
  }

  private func writeTemporary(_ image: CGImage, prefix: String) throws -> URL {
    try? FileManager.default.createDirectory(at: exchangeFolder, withIntermediateDirectories: true)
    let url = exchangeFolder.appendingPathComponent("\(prefix)-\(UUID().uuidString).png")
    guard PSSender.writePNG(image, to: url) else { throw PSCutoutError.cannotWrite }
    return url
  }

  /// The answer of the app as the text to show: nil when it took the message.
  private func problem(in answer: [String: Any]?) -> String? {
    guard let answer else { return text(.noAnswerFromApp) }
    if answer["type"] as? String == "error" { return answer["text"] as? String ?? text(.noAnswerFromApp) }
    if let problems = answer["problems"] as? [String], !problems.isEmpty { return problems.joined(separator: "\n") }
    return nil
  }

  func sendCutoutAsStartImage(contribute: PSContribute) async {
    let size = cutoutImage.map { (width: $0.width, height: $0.height) }
    await sendCutout(contribute: contribute) { PSCutoutActions.startImageBody(file: $0, width: size?.width ?? 0, height: size?.height ?? 0) }
  }

  func addCutoutToMoodboard(contribute: PSContribute) async { await sendCutout(contribute: contribute, body: PSCutoutActions.moodboardBody) }

  private func sendCutout(contribute: PSContribute, body: (URL) -> [String: Any]) async {
    error = nil
    guard let image = cutoutImage else {
      error = text(.cutoutNothing)
      return
    }
    do {
      let file = try writeTemporary(image, prefix: "panorama-360-cutout")
      error = problem(in: await contribute(body(file)))
    } catch {
      self.error = text(.sendFailed)
    }
  }

  func saveCutout(to url: URL) throws {
    guard let image = cutoutImage else { throw PSCutoutError.nothingExtracted }
    guard PSSender.writePNG(image, to: url) else { throw PSCutoutError.cannotWrite }
  }

  /// The retouched picture becomes a sticker where the cutout was taken, the canvas is shown and the sticker selected.
  func putBackAsSticker() {
    error = nil
    guard putBackReason == nil, let memory = doc.lastCutout, let patch = PSCutout.patch(memory: memory, lastResult: lastResultURL) else {
      error = text(.putBackOff)
      return
    }
    guard let folder = projectFolder else {
      error = text(.openProjectFirst)
      return
    }
    do {
      let picture = try addPicture(patch, folder)
      let sticker = Sticker(name: patch.lastPathComponent, file: picture.file, yaw: memory.yaw, pitch: memory.pitch, rot: 0, hfov: memory.fov)
      mutate {
        $0.stickers.append(sticker)
        $0.selectedID = sticker.id
        $0.viewMode = .plane
        $0.source = .canvas
        $0.lastCutout?.patchPath = patch.path
      }
    } catch {
      self.error = text(.unreadableFile, patch.lastPathComponent)
    }
  }

  /// The retouched picture is pasted on the panorama the cutout was taken from, with a soft edge, and the montage goes to the Results.
  func putBackInPanorama(contribute: PSContribute) async {
    error = nil
    guard putBackInPanoramaReason == nil, let memory = doc.lastCutout, let patchURL = PSCutout.patch(memory: memory, lastResult: lastResultURL),
      let backgroundPath = memory.resultPathAtExtraction, let background = PSResultLoader.load(URL(fileURLWithPath: backgroundPath), maxSide: nil),
      let patch = PSResultLoader.load(patchURL)
    else {
      error = text(.putBackOff)
      return
    }
    isSending = true
    defer { isSending = false }
    let folder = projectFolder
    do {
      let place = Sticker(name: "patch", file: "", yaw: memory.yaw, pitch: memory.pitch, rot: 0, hfov: memory.fov)
      var layer = PSLayer(
        image: patch, basis: PSProjection.basis(for: place, aspect: Double(patch.width) / Double(patch.height)), opacity: 1)
      layer.feather = 0.03
      let montage = try PSRendererFactory.make().render([layer], width: background.width, height: background.height, uOffset: 0, background: background)
      let file = try writeTemporary(montage, prefix: "panorama-360-montage")
      let description = text(.montageDescription, memory.yaw, memory.pitch, memory.fov)
      if let message = problem(in: await contribute(PSCutoutActions.montageBody(file: file, description: description))) {
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
