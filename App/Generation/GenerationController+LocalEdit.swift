import CoreGraphics
import Foundation
import HubCore
import HubKit
import ImageIO
import UniformTypeIdentifiers

/// Local editing on the Generation side: while a crop of the start image is retouched the tab makes
/// pictures of exactly the crop's size, and the confirm puts the chosen retouch back into the whole image.
extension GenerationController {
  /// The retouches made since the session opened, newest first; empty without a session.
  var localEditAttempts: [GeneratedImage] {
    guard let localEdit = control.inputs.localEdit else { return [] }
    return LocalEditAttempts.select(session.results, session: localEdit) { [self] in localEditPixelSize(of: $0) }
  }

  /// Opens a local edit on `rect` of the start image. The store keeps the tab's size, to give back at the
  /// end; the size of the crop comes through `localEditChanged`.
  func beginLocalEdit(rect: PixelRect) async throws(ControlError) {
    try await control.beginLocalEdit(
      rect: rect, generation: (parameters.width, parameters.height, parameters.highRes))
  }

  /// Puts the crop's size on the tab when a session is open (after a project's parameters were applied).
  func applyLocalEditSize() {
    guard let localEdit = control.inputs.localEdit else { return }
    setLocalEditSize(
      width: localEdit.rect.width, height: localEdit.rect.height,
      highRes: max(localEdit.rect.width, localEdit.rect.height) > 2048)
  }

  /// Follows the Control store: a session that opens puts the crop's size on the tab, one that closes gives
  /// back the size it remembered.
  func localEditChanged(from old: LocalEditSession?, to new: LocalEditSession?) {
    if new != nil {
      applyLocalEditSize()
    } else if let old {
      setLocalEditSize(width: old.generationWidth, height: old.generationHeight, highRes: old.generationHighRes)
    }
  }

  /// Confirms the session with `attempt`: the montage of the whole image is saved as a result (with the
  /// attempt's job at the whole image's size), becomes the start image, and the other attempts go to the
  /// Trash. Any failure before the Control store takes the montage leaves everything as it was; a session
  /// cancelled, undone or replaced meanwhile throws `localEditChanged` and nothing is put back. Returns the
  /// attempts the Trash refused, one line each.
  @discardableResult
  func confirmLocalEdit(attempt: GeneratedImage) async throws(ControlError) -> [String] {
    guard !isConfirmingLocalEdit, let localEdit = control.inputs.localEdit else { return [] }
    isConfirmingLocalEdit = true
    defer { isConfirmingLocalEdit = false }
    let sessionID = localEdit.id
    // The attempts the user saw when confirming; nothing made later goes to the Trash.
    let others = localEditAttempts.filter { $0.id != attempt.id }.map(\.id)
    let original = localEdit.original
    guard let request = control.originalPreviewRequest(maxPixel: max(original.pixelWidth, original.pixelHeight))
    else { throw .unreadable(original.name) }
    let attemptName = attempt.fileURL?.lastPathComponent ?? String(localized: "results.unsaved.name")
    let fileURL = attempt.fileURL
    let shown = attempt.image
    let rect = localEdit.rect
    let matchColors = localEdit.matchColors
    let made = await Task.detached(priority: .userInitiated) { () -> Result<(url: URL, data: Data), ControlError> in
      guard let whole = request.render() else { return .failure(.unreadable(original.name)) }
      let retouch = fileURL.flatMap { PNGImageStore.image(at: $0, maxPixel: max(rect.width, rect.height)) } ?? shown
      guard
        let montage = LocalEditCompositor.montage(
          original: whole, retouch: retouch, rect: rect, matchColors: matchColors)
      else { return .failure(.unreadable(attemptName)) }
      guard let data = Self.pngData(of: montage) else { return .failure(.cannotSave("montage")) }
      let folder = FileManager.default.temporaryDirectory.appendingPathComponent("DTHub-localEdit", isDirectory: true)
      let url = folder.appendingPathComponent("\(UUID().uuidString).png")
      do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: url)
      } catch {
        return .failure(.cannotSave(error.localizedDescription))
      }
      return .success((url, data))
    }.value
    let montage = try made.get()
    defer { try? FileManager.default.removeItem(at: montage.url) }
    guard control.inputs.localEdit?.id == sessionID else { throw .localEditChanged }

    var parameters = attempt.job.parameters
    parameters.width = original.pixelWidth
    parameters.height = original.pixelHeight
    let job = GenerationJob(
      prompt: attempt.job.prompt, negativePrompt: attempt.job.negativePrompt, model: attempt.job.model,
      parameters: parameters, imageStrength: attempt.job.imageStrength, moodboardCount: attempt.job.moodboardCount,
      maskSettings: attempt.job.maskSettings, videoFPS: attempt.job.videoFPS)
    guard await session.adopt(fileAt: montage.url, job: job) else { throw .unreadable(attemptName) }
    let adopted = session.results.first?.id

    // The montage belongs to this session only: when it changed meanwhile, the montage leaves again.
    let base = (original.name as NSString).deletingPathExtension
    do throws(ControlError) {
      guard control.inputs.localEdit?.id == sessionID else { throw .localEditChanged }
      try control.confirmLocalEdit(sessionID: sessionID, montage: montage.data, name: "\(base) (local edit).png")
    } catch {
      if let adopted { session.remove([adopted]) }
      throw error
    }
    return session.remove(Set(others))
  }

  /// The size of a result's picture: read from its file (`image` is a reduced copy), once per result.
  private func localEditPixelSize(of result: GeneratedImage) -> (width: Int, height: Int)? {
    if let known = localEditPixelSizes[result.id] { return known }
    let size: (width: Int, height: Int)?
    if let url = result.fileURL {
      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let width = properties[kCGImagePropertyPixelWidth] as? Int,
        let height = properties[kCGImagePropertyPixelHeight] as? Int
      else { return nil }
      size = (width, height)
    } else {
      // A picture that was never saved keeps its full size in `image`.
      size = (result.image.width, result.image.height)
    }
    localEditPixelSizes[result.id] = size
    return size
  }

  /// Width, height and HiRes for the session; a ratio lock follows the new size.
  private func setLocalEditSize(width: Int, height: Int, highRes: Bool) {
    parameters.highRes = highRes
    restoreDimensions(Size(width: width, height: height))
  }

  nonisolated private static func pngData(of image: CGImage) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
  }
}
