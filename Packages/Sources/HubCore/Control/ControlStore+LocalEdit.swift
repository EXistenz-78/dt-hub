import CoreGraphics
import Foundation
import HubKit

/// Local editing: a crop of the start image becomes the start image while it is retouched, then the
/// retouch is put back into the whole image (confirm) or the whole image comes back (cancel). Each is
/// one step of the history.
extension ControlStore {
  /// The source of a crop made for local editing.
  static let localEditSource = ReferenceImage.Source.plugin(id: "localEdit")

  /// Makes the crop `rect` (pixels of the start image) the start image, with the mask and the drawing
  /// cut to it; the session keeps the whole image, the framing, mask, drawing, strength and fill from
  /// before, and the Generation tab's size (`generation`) to give back when it closes. Nothing without
  /// a start image; refused when a session is already open. The pictures are cut away from the main actor;
  /// when the start image changes meanwhile nothing opens.
  public func beginLocalEdit(
    rect: PixelRect, generation: (width: Int, height: Int, highRes: Bool), now: Date = .now
  ) async throws(ControlError) {
    guard inputs.localEdit == nil else { throw .localEditOpen }
    guard let original = inputs.image else { return }
    let (mask, paint, storage) = (inputs.mask, inputs.paint, storage)
    let cuts = await Task.detached(priority: .userInitiated) {
      Self.localEditCuts(of: original, mask: mask, paint: paint, rect: rect, storage: storage)
    }.value
    guard inputs.localEdit == nil else { throw .localEditOpen }
    guard inputs.image == original else { return }
    // The mask or the drawing changed while the pictures were cut: cut them again.
    guard inputs.mask == mask, inputs.paint == paint else {
      return try await beginLocalEdit(rect: rect, generation: generation, now: now)
    }
    let cut = try cuts.get()
    let base = (original.name as NSString).deletingPathExtension
    let crop = try reference(from: cut.crop, name: "\(base) (crop).png", source: Self.localEditSource)

    var next = inputs
    next.image = crop
    next.framing = Framing()
    next.mask = nil
    next.paint = nil
    if let part = cut.mask {
      next.mask = MaskReference(fileName: try storage.save(part.png, name: "mask.png").fileName, coverage: part.coverage)
    }
    if let png = cut.paint {
      next.paint = PaintReference(fileName: try storage.save(png, name: "drawing.png").fileName)
    }
    next.localEdit = LocalEditSession(
      id: UUID(), rect: rect, original: original, framing: inputs.framing, mask: inputs.mask, paint: inputs.paint,
      strength: inputs.strength, marginFill: inputs.marginFill, generationWidth: generation.width,
      generationHeight: generation.height, generationHighRes: generation.highRes, openedAt: now)
    commit(next)
  }

  /// Puts the montage (the whole image with the retouch in it, PNG or other image bytes) as the start
  /// image, with the framing, mask, drawing, strength and fill from before the session, and closes it.
  /// Nothing without a session.
  public func confirmLocalEdit(montage data: Data, name: String) throws(ControlError) {
    guard let session = inputs.localEdit else { return }
    let montage = try reference(from: data, name: name, source: .result)
    commit(closing(session, with: montage))
  }

  /// Puts the whole image back, with everything from before the session, and closes it.
  public func cancelLocalEdit() {
    guard let session = inputs.localEdit else { return }
    commit(closing(session, with: session.original))
  }

  /// The whole image of the open session, or the start image without one, its longest side at most
  /// `maxPixel` (nil: full size).
  public func originalImage(maxPixel: Int?) -> CGImage? {
    guard let image = inputs.localEdit?.original ?? inputs.image else { return nil }
    return storage.image(named: image.fileName, maxPixel: maxPixel ?? max(image.pixelWidth, image.pixelHeight))
  }

  /// The preview of the whole image of the open session (or of the start image without one), to be
  /// decoded away from the main actor.
  public func originalPreviewRequest(maxPixel: Int) -> PreviewRequest? {
    guard let image = inputs.localEdit?.original ?? inputs.image else { return nil }
    return PreviewRequest(storage: storage, fileName: image.fileName, maxPixel: maxPixel)
  }

  /// The inputs with `image` as the start image and the state the session remembers.
  private func closing(_ session: LocalEditSession, with image: ReferenceImage) -> ControlInputs {
    var next = inputs
    next.image = image
    next.framing = session.framing
    next.mask = session.mask
    next.paint = session.paint
    next.strength = session.strength
    next.marginFill = session.marginFill
    next.localEdit = nil
    return next
  }

  /// The crop, mask and drawing of a local edit, as PNG bytes ready to be saved.
  struct LocalEditCuts: Sendable {
    let crop: Data
    /// The mask cut to the crop, with its coverage; nil when nothing of it falls in the crop.
    let mask: (png: Data, coverage: Double)?
    let paint: Data?
  }

  /// Decodes the whole image, the mask and the drawing and cuts them to `rect`: the heavy part of
  /// `beginLocalEdit`, run away from the main actor.
  nonisolated static func localEditCuts(
    of original: ReferenceImage, mask: MaskReference?, paint: PaintReference?, rect: PixelRect,
    storage: any ReferenceStorage
  ) -> Result<LocalEditCuts, ControlError> {
    let (fullWidth, fullHeight) = (original.pixelWidth, original.pixelHeight)
    guard
      let whole = storage.image(named: original.fileName, maxPixel: max(fullWidth, fullHeight)),
      whole.width == fullWidth, whole.height == fullHeight,
      let cropped = LocalEditCompositor.crop(whole, to: rect), let crop = pngData(of: cropped)
    else { return .failure(.unreadable(original.name)) }
    let working = MaskBitmap.workingSize(imageWidth: rect.width, imageHeight: rect.height)
    var maskPart: (png: Data, coverage: Double)?
    if let mask, let stored = storage.image(named: mask.fileName, maxPixel: MaskBitmap.maxSide),
      let part = LocalEditCompositor.crop(stored, to: rect, fullWidth: fullWidth, fullHeight: fullHeight),
      let bitmap = maskBitmap(part, width: working.width, height: working.height), !bitmap.isEmpty
    {
      guard let png = bitmap.pngData() else { return .failure(.cannotSave("mask")) }
      maskPart = (png, bitmap.coverage)
    }
    var paintPart: Data?
    if let paint, let stored = storage.image(named: paint.fileName, maxPixel: MaskBitmap.maxSide),
      let part = cut(stored, to: rect, fullWidth: fullWidth, fullHeight: fullHeight),
      let bitmap = PaintBitmap.fitted(from: part, width: working.width, height: working.height), !bitmap.isEmpty
    {
      guard let png = bitmap.pngData() else { return .failure(.cannotSave("drawing")) }
      paintPart = png
    }
    return .success(LocalEditCuts(crop: crop, mask: maskPart, paint: paintPart))
  }

  /// The part of a drawing (saved smaller than the whole image) that covers `rect` of the whole image,
  /// transparency kept (`LocalEditCompositor.crop` makes it opaque).
  nonisolated private static func cut(_ image: CGImage, to rect: PixelRect, fullWidth: Int, fullHeight: Int) -> CGImage? {
    guard fullWidth > 0, fullHeight > 0 else { return nil }
    let sx = Double(image.width) / Double(fullWidth)
    let sy = Double(image.height) / Double(fullHeight)
    let x0 = Int((Double(rect.x) * sx).rounded()), y0 = Int((Double(rect.y) * sy).rounded())
    let x1 = Int((Double(rect.x + rect.width) * sx).rounded())
    let y1 = Int((Double(rect.y + rect.height) * sy).rounded())
    guard x0 >= 0, y0 >= 0, x1 > x0, y1 > y0, x1 <= image.width, y1 <= image.height else { return nil }
    return image.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
  }

  /// A mask from a picture, stretched to `width × height`.
  nonisolated private static func maskBitmap(_ image: CGImage, width: Int, height: Int) -> MaskBitmap? {
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
    else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage().flatMap(MaskBitmap.init(image:))
  }
}
