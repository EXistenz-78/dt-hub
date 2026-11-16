import Foundation
import HubKit

extension ControlStore {
  /// The copies the inputs refer to: start image, mask, drawing and Moodboard pictures.
  private static func fileNames(of inputs: ControlInputs) -> [String] {
    var names: [String] = []
    if let image = inputs.image { names.append(image.fileName) }
    if let mask = inputs.mask { names.append(mask.fileName) }
    if let paint = inputs.paint { names.append(paint.fileName) }
    names += inputs.moodboard.map(\.image.fileName)
    return names
  }

  /// Copies the files the inputs refer to into `folder` (same names) so a queue entry owns its pictures: Control's
  /// own garbage collection never touches that folder. Returns the inputs, whose file names are now relative to it.
  /// A local edit is left out: the RUN only needs the crop, which is the start image.
  public func captureForQueue(into folder: URL) throws(ControlError) -> ControlInputs {
    var captured = inputs
    captured.localEdit = nil
    let names = Self.fileNames(of: captured)
    guard !names.isEmpty else { return captured }
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      for name in names {
        let target = folder.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: storage.url(for: name), to: target)
      }
    } catch {
      throw .cannotSave(error.localizedDescription)
    }
    return captured
  }

  /// Puts the inputs of a queue entry on the Control tab: copies their files from `folder` into Control's storage and
  /// applies them as one step of the history (Undo brings back what was there). A missing file throws `unreadable`
  /// and nothing is changed. While a local edit is open only an entry of the same crop is taken (the session stays
  /// open); any other throws `localEditOpen` and nothing is changed.
  public func restoreFromQueue(_ restored: ControlInputs, from folder: URL) throws(ControlError) {
    var restored = restored
    if let session = inputs.localEdit {
      guard restored.image?.id == inputs.image?.id else { throw .localEditOpen }
      restored.localEdit = session
    }
    let names = Self.fileNames(of: restored)
    for name in names where !FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
      throw .unreadable(name)
    }
    for name in names {
      let target = storage.url(for: name)
      guard !FileManager.default.fileExists(atPath: target.path) else { continue }
      do {
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: folder.appendingPathComponent(name), to: target)
      } catch {
        throw .cannotSave(error.localizedDescription)
      }
    }
    commit(restored)
  }
}
