import CoreGraphics
import Foundation

/// The queue of the app (`queue.capture`, `queue.prepare`): the picture and the choices of a prepared enlargement are kept with
/// a queue entry and put back when the entry runs. Only the starting point is kept: the tiles are made again by the run.
extension TUState {
  static let queuePictureName = "source.png"

  /// The snapshot for the queue, or nil when nothing is prepared. The picture goes into `folder` as a PNG.
  func queueCapture(folder: URL) -> [String: Any]? {
    guard isPrepared, let image, let png = TUImage.pngData(image) else { return nil }
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try png.write(to: folder.appendingPathComponent(Self.queuePictureName), options: .atomic)
      let encoded = try JSONEncoder().encode(currentChoice)
      guard let choice = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else { return nil }
      return ["image": Self.queuePictureName, "imageName": imageName, "choice": choice]
    } catch {
      return nil
    }
  }

  /// Puts a snapshot back and proposes the pipeline to the app, with no question asked (the entry was approved when it was
  /// queued). `model` and `family` are the header's for the entry: this tab may not have been told. Nil when it is prepared,
  /// otherwise why not.
  func queuePrepare(
    folder: URL, state: [String: Any], model: String?, family: String?,
    contribute: ([String: Any]) async -> [String: Any]?, registerPreset: ([String: Any]) async -> [String: Any]?
  ) async -> String? {
    guard let file = state["image"] as? String, !file.contains("/"),
      let loaded = TUImage.load(folder.appendingPathComponent(file))
    else { return text(.unreadableImage) }
    guard let raw = state["choice"], let data = try? JSONSerialization.data(withJSONObject: raw),
      let choice = try? JSONDecoder().decode(TUChoice.self, from: data), TileOverlap(rawValue: choice.overlap) != nil,
      TUSettings.factors.contains(choice.factor)
    else { return text(.queueBadState) }
    if let model { self.model = model }
    if let family { self.family = family }
    setImage(loaded, name: state["imageName"] as? String ?? file)
    // After the picture: choosing it sets the tile size by itself, and the entry's own size must win.
    applyChoice(choice, save: true)
    await prepare(confirmed: true, contribute: contribute, registerPreset: registerPreset)
    return isPrepared ? nil : (notice ?? text(.notAnswered))
  }
}
