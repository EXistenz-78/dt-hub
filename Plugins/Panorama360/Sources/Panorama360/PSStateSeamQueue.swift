import Foundation

/// The queue of the app (`queue.capture`, `queue.prepare`): the panorama a prepared correction was made from is kept with a
/// queue entry and the correction is made again from that copy when the entry runs. The mask and the composition are worked out
/// again by `PSSeamSession`; nothing of a run in progress is kept.
extension PSState {
  /// The snapshot for the queue, or nil when no correction is prepared. The panorama is copied into `folder`.
  func queueCapture(folder: URL) -> [String: Any]? {
    guard isSeamPrepared, seamSession != nil, let path = seamSourcePath else { return nil }
    let source = URL(fileURLWithPath: path)
    let name = "panorama." + (source.pathExtension.isEmpty ? "png" : source.pathExtension)
    let target = folder.appendingPathComponent(name)
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try? FileManager.default.removeItem(at: target)
      try FileManager.default.copyItem(at: source, to: target)
    } catch {
      return nil
    }
    return ["panorama": name]
  }

  /// Makes the correction again from the copy in `folder` and proposes it to the app. The result shown in the tab is not
  /// touched. `model` is the header's for the entry. Nil when it is prepared, otherwise why not.
  func queuePrepare(
    folder: URL, state: [String: Any], model: String?, contribute: PSContribute
  ) async -> String? {
    guard let name = state["panorama"] as? String, !name.contains("/") else { return text(.seamUnreadable) }
    let file = folder.appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: file.path) else { return text(.seamUnreadable) }
    if let model { modelFile = model }
    isSending = true
    defer { isSending = false }
    return await proposeSeamCorrection(panorama: file.path, contribute: contribute)
  }
}
