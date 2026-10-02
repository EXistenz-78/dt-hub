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
  /// At launch the copy of the saved image was gone.
  case missingAtLaunch(name: String)
}

/// A reason to look before pressing RUN; shown in the strip.
public enum ControlWarning: Hashable, Sendable {
  /// The framing cuts off this much of the image (more than a third).
  case strongCrop(percent: Int)
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
    let stored = try storage.save(data, name: name)
    let image = ReferenceImage(
      id: UUID(), name: name, pixelWidth: stored.pixelWidth, pixelHeight: stored.pixelHeight, source: source,
      fileName: stored.fileName)
    var next = inputs
    next.image = image
    next.framing = Framing()
    let replaced = inputs.image
    commit(next)
    notice = replaced.map { .replaced(name: $0.name) }
  }

  /// A picture that only exists in memory (a result that could not be saved): stored as PNG.
  public func setImage(_ image: CGImage, name: String, source: ReferenceImage.Source) throws(ControlError) {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    else { throw .cannotSave(name) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw .cannotSave(name) }
    try setImage(data: data as Data, name: name, source: source)
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
    commit(next)
    notice = .removed(name: image.name)
  }

  /// Takes everything out of the tab.
  public func clear() {
    guard inputs != ControlInputs() else { return }
    commit(ControlInputs())
    notice = .cleared
  }

  // MARK: Strength and framing (not part of the history)

  /// nil goes back to the automatic strength.
  public func setStrength(_ value: Double?) {
    inputs.strength = value.map { min(1, max(0, $0)) }
    save()
  }

  public func setOffset(x: Double, y: Double) {
    inputs.framing = Framing(mode: inputs.framing.mode, offsetX: x, offsetY: y).clamped()
    save()
  }

  // MARK: History

  public func undo() {
    guard let previous = undoStack.popLast() else { return }
    redoStack.append(inputs)
    inputs = previous
    historyVersion += 1
    notice = nil
    save()
    collectGarbage()
  }

  public func redo() {
    guard let next = redoStack.popLast() else { return }
    undoStack.append(inputs)
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

  // MARK: Warnings and RUN

  public func warnings(canvasWidth: Int, canvasHeight: Int) -> [ControlWarning] {
    guard let image = inputs.image else { return [] }
    let loss = FramingMath.loss(
      imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth, canvasHeight: canvasHeight)
    return loss.fraction > 1.0 / 3.0 ? [.strongCrop(percent: Int((loss.fraction * 100).rounded()))] : []
  }

  /// What a RUN needs to prepare its inputs, to be rendered away from the main actor.
  public func pendingInputs(canvasWidth: Int, canvasHeight: Int) -> PendingInputs {
    PendingInputs(
      storage: storage, image: inputs.image, framing: inputs.framing, canvasWidth: canvasWidth,
      canvasHeight: canvasHeight)
  }

  // MARK: Private

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
    }
    for name in storage.allFileNames() where !referenced.contains(name) { storage.remove(name) }
  }
}

/// The start image and canvas of a RUN, ready to be framed on a background thread.
public struct PendingInputs: Sendable {
  let storage: any ReferenceStorage
  let image: ReferenceImage?
  let framing: Framing
  let canvasWidth: Int
  let canvasHeight: Int

  /// Decodes the copy at the size the canvas needs (a 50-megapixel photo is not decoded whole)
  /// and frames it. No image: the RUN is text-to-image.
  public func render() throws(ControlError) -> GenerationInputs {
    guard let image else { return .none }
    let scale = max(Double(canvasWidth) / Double(image.pixelWidth), Double(canvasHeight) / Double(image.pixelHeight))
    let longest = max(image.pixelWidth, image.pixelHeight)
    let maxPixel = scale < 1 ? Int((Double(longest) * scale).rounded(.up)) + 1 : longest
    guard let decoded = storage.image(named: image.fileName, maxPixel: maxPixel),
      let framed = InputComposer.frame(decoded, toWidth: canvasWidth, height: canvasHeight, framing: framing)
    else { throw .unreadable(image.name) }
    return GenerationInputs(image: framed)
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
