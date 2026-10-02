import CoreGraphics
import Foundation
import HubKit
import ImageIO
import Observation
import UniformTypeIdentifiers

/// What the Control tab says about the last change; the app shows it as a message, with
/// "Undo" where the change can be undone.
public enum ControlNotice: Equatable, Sendable {
  case removed(name: String)
  case replaced(name: String)
  case cleared
  /// At launch the copy of the saved mask was gone.
  case maskMissingAtLaunch
  /// At launch the copy of the saved drawing was gone.
  case paintMissingAtLaunch
  /// At launch the copy of the saved image was gone.
  case missingAtLaunch(name: String)
}

/// A reason to look before pressing RUN; shown in the strip.
public enum ControlWarning: Hashable, Sendable {
  /// The framing cuts off this much of the image (more than a third).
  case strongCrop(percent: Int)
  /// More than three Moodboard pictures are on: each one adds render time more than linearly.
  case manyReferences(count: Int)
  /// The chosen model does not use the Moodboard, and pictures are on.
  case moodboardIgnored
}

/// The Control tab's inputs, kept and saved (tab Control spec §4): the start image with its
/// framing and strength, the copies on disk, the history for Undo.
@MainActor
@Observable
public final class ControlStore {
  public private(set) var inputs: ControlInputs
  public private(set) var notice: ControlNotice?
  /// Changes with every step of the history, so `canUndo` and `canRedo` can be observed (the
  /// stacks themselves are not).
  private var historyVersion = 0

  @ObservationIgnored private let storage: any ReferenceStorage
  @ObservationIgnored private let fileURL: URL
  @ObservationIgnored private let undoLimit: Int
  @ObservationIgnored private var undoStack: [ControlInputs] = []
  @ObservationIgnored private var redoStack: [ControlInputs] = []

  /// Restores `fileURL` (an image whose copy is gone is dropped, with a notice) and sweeps the
  /// copies nothing refers to.
  public init(storage: any ReferenceStorage, fileURL: URL, undoLimit: Int = 20) {
    self.storage = storage
    self.fileURL = fileURL
    self.undoLimit = undoLimit
    var loaded = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(ControlInputs.self, from: $0) }
      ?? ControlInputs()
    if let image = loaded.image, !storage.exists(image.fileName) {
      loaded.image = nil
      loaded.framing = Framing()
      notice = .missingAtLaunch(name: image.name)
    }
    if let mask = loaded.mask, !storage.exists(mask.fileName) {
      loaded.mask = nil
      notice = .maskMissingAtLaunch
    }
    if let paint = loaded.paint, !storage.exists(paint.fileName) {
      loaded.paint = nil
      notice = .paintMissingAtLaunch
    }
    for entry in loaded.moodboard where !storage.exists(entry.image.fileName) {
      loaded.moodboard.removeAll { $0.id == entry.id }
      notice = .missingAtLaunch(name: entry.image.name)
    }
    inputs = loaded
    save()
    collectGarbage()
  }

  /// ~/Library/Application Support/DT Hub/control.json.
  public static var defaultFileURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true)
      .appendingPathComponent("control.json")
  }

  public var canUndo: Bool {
    _ = historyVersion
    return !undoStack.isEmpty
  }

  public var canRedo: Bool {
    _ = historyVersion
    return !redoStack.isEmpty
  }

  // MARK: Image

  /// Takes a picture from its bytes: copies it, describes it, and makes it the start image
  /// (the one there was, if any, can be brought back with `undo`). The framing starts centered.
  public func setImage(data: Data, name: String, source: ReferenceImage.Source) throws(ControlError) {
    let image = try reference(from: data, name: name, source: source)
    var next = inputs
    next.image = image
    next.framing = Framing()
    next.mask = nil  // drawn over the other picture
    next.paint = nil
    let replaced = inputs.image
    commit(next)
    notice = replaced.map { .replaced(name: $0.name) }
  }

  /// A picture that only exists in memory (a result that could not be saved): stored as PNG.
  public func setImage(_ image: CGImage, name: String, source: ReferenceImage.Source) throws(ControlError) {
    guard let data = Self.pngData(of: image) else { throw .cannotSave(name) }
    try setImage(data: data, name: name, source: source)
  }

  /// Takes a file (from the Finder, or an image the Results window saved); reads it away from
  /// the main actor. `source` defaults to the file itself.
  public func setImage(fileURL url: URL, source: ReferenceImage.Source? = nil) async throws(ControlError) {
    let name = url.lastPathComponent
    let data = await Task.detached { try? Data(contentsOf: url) }.value
    guard let data else { throw .unreadable(name) }
    try setImage(data: data, name: name, source: source ?? .file(path: url.path))
  }

  public func removeImage() {
    guard let image = inputs.image else { return }
    var next = inputs
    next.image = nil
    next.framing = Framing()
    next.mask = nil
    next.paint = nil
    commit(next)
    notice = .removed(name: image.name)
  }

  /// Takes everything out of the tab.
  public func clear() {
    guard inputs != ControlInputs() else { return }
    commit(ControlInputs())
    notice = .cleared
  }

  // MARK: Mask

  /// The mask as it is drawn, nil when there is none.
  public func maskBitmap() -> MaskBitmap? {
    guard let mask = inputs.mask, let image = storage.image(named: mask.fileName, maxPixel: MaskBitmap.maxSide)
    else { return nil }
    return MaskBitmap(image: image)
  }

  /// The size a mask over the start image is drawn at; nil without an image.
  public var maskSize: (width: Int, height: Int)? {
    inputs.image.map { MaskBitmap.workingSize(imageWidth: $0.pixelWidth, imageHeight: $0.pixelHeight) }
  }

  /// Takes the mask as drawn (one step of the history). An empty mask is no mask. Nothing without
  /// a start image.
  public func commitMask(_ bitmap: MaskBitmap) throws(ControlError) {
    guard inputs.image != nil else { return }
    var next = inputs
    if bitmap.isEmpty {
      guard inputs.mask != nil else { return }
      next.mask = nil
    } else {
      guard let data = bitmap.pngData() else { throw .cannotSave("mask") }
      let stored = try storage.save(data, name: "mask.png")
      next.mask = MaskReference(fileName: stored.fileName, coverage: bitmap.coverage)
    }
    commit(next)
  }

  /// Paints what was clear and clears what was painted (a mask not drawn yet becomes everything).
  public func invertMask() throws(ControlError) {
    guard let size = maskSize else { return }
    var bitmap = maskBitmap() ?? MaskBitmap(width: size.width, height: size.height)
    bitmap.invert()
    try commitMask(bitmap)
  }

  public func clearMask() {
    guard inputs.mask != nil else { return }
    var next = inputs
    next.mask = nil
    commit(next)
  }

  /// How Draw Things treats the mask; not part of the history.
  public func setMaskSettings(_ settings: MaskSettings) {
    inputs.maskSettings = settings.clamped()
    save()
  }

  // MARK: Drawing (the Brush)

  /// The drawing as it is, nil when there is none.
  public func paintBitmap() -> PaintBitmap? {
    guard let paint = inputs.paint, let image = storage.image(named: paint.fileName, maxPixel: MaskBitmap.maxSide)
    else { return nil }
    return PaintBitmap(image: image)
  }

  /// Takes the drawing as it is (one step of the history). An empty drawing is no drawing. Nothing
  /// without a start image.
  public func commitPaint(_ bitmap: PaintBitmap) throws(ControlError) {
    guard inputs.image != nil else { return }
    var next = inputs
    if bitmap.isEmpty {
      guard inputs.paint != nil else { return }
      next.paint = nil
    } else {
      guard let data = bitmap.pngData() else { throw .cannotSave("drawing") }
      let stored = try storage.save(data, name: "drawing.png")
      next.paint = PaintReference(fileName: stored.fileName)
    }
    commit(next)
  }

  public func clearPaint() {
    guard inputs.paint != nil else { return }
    var next = inputs
    next.paint = nil
    commit(next)
  }

  // MARK: Moodboard

  /// Adds a picture to the Moodboard (on, at the end).
  public func addMoodboardImage(data: Data, name: String, source: ReferenceImage.Source) throws(ControlError) {
    let image = try reference(from: data, name: name, source: source)
    var next = inputs
    next.moodboard.append(MoodboardEntry(image: image))
    commit(next)
  }

  public func addMoodboardImage(_ image: CGImage, name: String, source: ReferenceImage.Source) throws(ControlError) {
    guard let data = Self.pngData(of: image) else { throw .cannotSave(name) }
    try addMoodboardImage(data: data, name: name, source: source)
  }

  public func addMoodboardImage(fileURL url: URL, source: ReferenceImage.Source? = nil) async throws(ControlError) {
    let name = url.lastPathComponent
    let data = await Task.detached { try? Data(contentsOf: url) }.value
    guard let data else { throw .unreadable(name) }
    try addMoodboardImage(data: data, name: name, source: source ?? .file(path: url.path))
  }

  /// A picture dropped on one that is there takes its place: the same position and switch.
  public func replaceMoodboardImage(
    id: UUID, data: Data, name: String, source: ReferenceImage.Source
  ) throws(ControlError) {
    guard let index = inputs.moodboard.firstIndex(where: { $0.id == id }) else { return }
    let old = inputs.moodboard[index]
    let image = try reference(from: data, name: name, source: source)
    var next = inputs
    next.moodboard[index] = MoodboardEntry(image: image, isOn: old.isOn)
    commit(next)
    notice = .replaced(name: old.image.name)
  }

  public func replaceMoodboardImage(
    id: UUID, fileURL url: URL, source: ReferenceImage.Source? = nil
  ) async throws(ControlError) {
    let name = url.lastPathComponent
    let data = await Task.detached { try? Data(contentsOf: url) }.value
    guard let data else { throw .unreadable(name) }
    try replaceMoodboardImage(id: id, data: data, name: name, source: source ?? .file(path: url.path))
  }

  public func removeMoodboardImage(id: UUID) {
    guard let entry = inputs.moodboard.first(where: { $0.id == id }) else { return }
    var next = inputs
    next.moodboard.removeAll { $0.id == id }
    commit(next)
    notice = .removed(name: entry.image.name)
  }

  /// Takes the whole Moodboard out (the start image stays).
  public func clearMoodboard() {
    guard !inputs.moodboard.isEmpty else { return }
    var next = inputs
    next.moodboard = []
    commit(next)
    notice = .cleared
  }

  /// A picture that is off is not sent but is not lost (not part of the history).
  public func setMoodboardOn(id: UUID, isOn: Bool) {
    guard let index = inputs.moodboard.firstIndex(where: { $0.id == id }) else { return }
    inputs.moodboard[index].isOn = isOn
    save()
  }

  /// Moves a picture before another one, or to the end when `before` is nil.
  public func moveMoodboardImage(id: UUID, before target: UUID?) {
    guard id != target, let from = inputs.moodboard.firstIndex(where: { $0.id == id }) else { return }
    var entries = inputs.moodboard
    let moved = entries.remove(at: from)
    if let target, let to = entries.firstIndex(where: { $0.id == target }) {
      entries.insert(moved, at: to)
    } else {
      entries.append(moved)
    }
    inputs.moodboard = entries
    save()
  }

  // MARK: Strength and framing (not part of the history)

  /// nil goes back to the automatic strength.
  public func setStrength(_ value: Double?) {
    inputs.strength = value.map { min(1, max(0, $0)) }
    save()
  }

  public func setOffset(x: Double, y: Double) {
    inputs.framing = Framing(zoom: inputs.framing.zoom, offsetX: x, offsetY: y).clamped()
    save()
  }

  // MARK: History

  public func undo() {
    guard var previous = undoStack.popLast() else { return }
    redoStack.append(inputs)
    previous.moodboard = Self.keepingSwitchesAndOrder(of: inputs.moodboard, in: previous.moodboard)
    Self.keepingSettings(of: inputs, in: &previous)
    inputs = previous
    historyVersion += 1
    notice = nil
    save()
    collectGarbage()
  }

  public func redo() {
    guard var next = redoStack.popLast() else { return }
    undoStack.append(inputs)
    next.moodboard = Self.keepingSwitchesAndOrder(of: inputs.moodboard, in: next.moodboard)
    Self.keepingSettings(of: inputs, in: &next)
    inputs = next
    historyVersion += 1
    notice = nil
    save()
    collectGarbage()
  }

  public func dismissNotice() {
    notice = nil
  }

  /// The start image decoded for the screen, its longest side at most `maxPixel`.
  public func preview(maxPixel: Int) -> CGImage? {
    guard let image = inputs.image else { return nil }
    return storage.image(named: image.fileName, maxPixel: maxPixel)
  }

  /// The same picture as `preview`, to be decoded away from the main actor.
  public func previewRequest(maxPixel: Int) -> PreviewRequest? {
    guard let image = inputs.image else { return nil }
    return PreviewRequest(storage: storage, fileName: image.fileName, maxPixel: maxPixel)
  }

  /// The preview of a Moodboard picture, to be decoded away from the main actor.
  public func previewRequest(ofMoodboard id: UUID, maxPixel: Int) -> PreviewRequest? {
    guard let entry = inputs.moodboard.first(where: { $0.id == id }) else { return nil }
    return PreviewRequest(storage: storage, fileName: entry.image.fileName, maxPixel: maxPixel)
  }

  /// Where the copy of a picture lives, to drag it out (to another card, or another app).
  public func copyURL(of image: ReferenceImage) -> URL? {
    storage.exists(image.fileName) ? storage.url(for: image.fileName) : nil
  }

  // MARK: Warnings and RUN

  /// What to look at before RUN. `usesMoodboard` is false for a model that ignores the Moodboard.
  public func warnings(canvasWidth: Int, canvasHeight: Int, usesMoodboard: Bool = true) -> [ControlWarning] {
    var warnings: [ControlWarning] = []
    if let image = inputs.image {
      let loss = FramingMath.loss(
        imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
        canvasHeight: canvasHeight)
      if loss.fraction > 1.0 / 3.0 { warnings.append(.strongCrop(percent: Int((loss.fraction * 100).rounded()))) }
    }
    let on = inputs.moodboard.filter(\.isOn).count
    if on > 0, !usesMoodboard {
      warnings.append(.moodboardIgnored)
    } else if on > 3 {
      warnings.append(.manyReferences(count: on))
    }
    return warnings
  }

  /// What a RUN needs to prepare its inputs, to be rendered away from the main actor. The Moodboard
  /// goes only when `includeMoodboard` (the model uses it).
  public func pendingInputs(canvasWidth: Int, canvasHeight: Int, includeMoodboard: Bool = true) -> PendingInputs {
    let sent = inputs.moodboard.filter(\.isOn).map { (image: $0.image, weight: 1.0) }
    return PendingInputs(
      storage: storage, image: inputs.image, mask: inputs.image == nil ? nil : inputs.mask,
      paint: inputs.image == nil ? nil : inputs.paint, framing: inputs.framing,
      canvasWidth: canvasWidth, canvasHeight: canvasHeight, moodboard: includeMoodboard ? sent : [])
  }

  // MARK: Private

  /// Copies the bytes into the Control folder and describes the picture.
  private func reference(
    from data: Data, name: String, source: ReferenceImage.Source
  ) throws(ControlError) -> ReferenceImage {
    let stored = try storage.save(data, name: name)
    return ReferenceImage(
      id: UUID(), name: name, pixelWidth: stored.pixelWidth, pixelHeight: stored.pixelHeight, source: source,
      fileName: stored.fileName)
  }

  /// The Moodboard of a state brought back by undo or redo: the pictures that are in both states
  /// keep the switch and the order they have now (neither is a step of the history); the ones that
  /// come back, or go, are as the saved state had them.
  private static func keepingSwitchesAndOrder(
    of current: [MoodboardEntry], in restored: [MoodboardEntry]
  ) -> [MoodboardEntry] {
    let now = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let saved = Dictionary(restored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var order = current.map(\.id).filter { saved[$0] != nil }[...]
    return restored.map { entry in
      guard now[entry.id] != nil, let id = order.popFirst(), var kept = saved[id] else { return entry }
      kept.isOn = now[id]?.isOn ?? kept.isOn
      return kept
    }
  }

  /// What undo and redo do not touch while the start image stays the same: the settings of the mask,
  /// the strength and the cut. None of them is a step of the history, so going back a stroke must not
  /// bring back what the user had set before it. When the step changes the image (a new picture, a
  /// removal, Clear all) the snapshot comes back whole, with the values it had.
  private static func keepingSettings(of current: ControlInputs, in restored: inout ControlInputs) {
    guard restored.image?.id == current.image?.id else { return }
    restored.maskSettings = current.maskSettings
    restored.strength = current.strength
    restored.framing = current.framing
  }

  nonisolated static func pngData(of image: CGImage) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
  }

  private func commit(_ next: ControlInputs) {
    undoStack.append(inputs)
    if undoStack.count > undoLimit { undoStack.removeFirst(undoStack.count - undoLimit) }
    redoStack = []
    inputs = next
    historyVersion += 1
    notice = nil
    save()
    collectGarbage()
  }

  private func save() {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(inputs).write(to: fileURL, options: .atomic)
    } catch {
      // A failed save only loses the restore at the next launch.
    }
  }

  /// Deletes the copies that neither the inputs nor the history refer to.
  private func collectGarbage() {
    var referenced = Set<String>()
    for state in undoStack + redoStack + [inputs] {
      if let image = state.image { referenced.insert(image.fileName) }
      if let mask = state.mask { referenced.insert(mask.fileName) }
      if let paint = state.paint { referenced.insert(paint.fileName) }
      for entry in state.moodboard { referenced.insert(entry.image.fileName) }
    }
    for name in storage.allFileNames() where !referenced.contains(name) { storage.remove(name) }
  }
}

/// The start image and canvas of a RUN, ready to be framed on a background thread.
public struct PendingInputs: Sendable {
  let storage: any ReferenceStorage
  let image: ReferenceImage?
  let mask: MaskReference?
  let paint: PaintReference?
  let framing: Framing
  let canvasWidth: Int
  let canvasHeight: Int
  /// The Moodboard pictures that are on, all with the same weight.
  let moodboard: [(image: ReferenceImage, weight: Double)]

  /// Longest side of a Moodboard picture when it is sent.
  static let moodboardPixels = 1024

  /// Decodes the start image at the size the canvas needs (a 50-megapixel photo is not decoded
  /// whole) and frames it; reduces and encodes the Moodboard pictures. Nothing: the RUN is
  /// text-to-image.
  public func render() throws(ControlError) -> GenerationInputs {
    var hints: [GenerationHint] = []
    for entry in moodboard {
      guard let decoded = storage.image(named: entry.image.fileName, maxPixel: Self.moodboardPixels),
        let data = ControlStore.pngData(of: decoded)
      else { throw .unreadable(entry.image.name) }
      hints.append(GenerationHint(imageData: data, weight: entry.weight))
    }
    guard let image else { return GenerationInputs(hints: hints) }
    let scale = max(Double(canvasWidth) / Double(image.pixelWidth), Double(canvasHeight) / Double(image.pixelHeight))
    let longest = max(image.pixelWidth, image.pixelHeight)
    let maxPixel = scale < 1 ? Int((Double(longest) * scale).rounded(.up)) + 1 : longest
    var layer: PaintBitmap?
    if let paint {
      guard let stored = storage.image(named: paint.fileName, maxPixel: MaskBitmap.maxSide),
        let bitmap = PaintBitmap(image: stored)
      else { throw .unreadable(image.name) }
      layer = bitmap
    }
    guard let decoded = storage.image(named: image.fileName, maxPixel: maxPixel),
      let framed = InputComposer.frame(
        decoded, toWidth: canvasWidth, height: canvasHeight, framing: framing, paint: layer)
    else { throw .unreadable(image.name) }
    guard let mask else { return GenerationInputs(image: framed, hints: hints) }
    guard let stored = storage.image(named: mask.fileName, maxPixel: MaskBitmap.maxSide),
      let bitmap = MaskBitmap(image: stored),
      let scaled = InputComposer.mask(
        bitmap, imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, toWidth: canvasWidth,
        height: canvasHeight, framing: framing)
    else { throw .unreadable(image.name) }
    return GenerationInputs(image: framed, hints: hints, mask: scaled)
  }
}

/// A preview to decode on a background thread.
public struct PreviewRequest: Sendable {
  let storage: any ReferenceStorage
  let fileName: String
  let maxPixel: Int

  public func render() -> CGImage? {
    storage.image(named: fileName, maxPixel: maxPixel)
  }
}
