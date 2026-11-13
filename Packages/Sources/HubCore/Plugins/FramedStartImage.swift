import Foundation
import HubKit

/// The start image as the canvas has it, written as a PNG in the plug-ins' temporary folder for the plug-ins that draw on
/// it (`PluginContext.startImageFramed`). The picture is made a moment after the framing stops changing (the sliders move
/// it continuously) and, until the new one is ready, the previous file stays on offer.
@MainActor
public final class FramedStartImage {
  private let folder: URL
  /// The key of the file at `path`.
  private var key: String?
  public private(set) var path: String?
  private var pendingKey: String?
  private var pending: Task<Void, Never>?
  private var counter = 0
  /// The number of the picture at `path`: one that was started earlier and ends later is not offered in its place.
  private var shown = 0
  /// Goes up when the start image goes away: a picture that was being made for it is thrown away.
  private var epoch = 0
  /// Called when a new picture is ready: the plug-ins are told again.
  public var onChange: (@MainActor () -> Void)?

  public init(folder: URL) { self.folder = folder }

  /// The file for the framing the Control tab has now, or the previous one while the new one is being made; nil without a
  /// start image.
  public func path(for control: ControlStore, canvasWidth: Int, canvasHeight: Int, fill: MarginFill) -> String? {
    guard let wanted = control.framedStartImageKey(canvasWidth: canvasWidth, canvasHeight: canvasHeight, fill: fill)
    else {
      reset()
      return nil
    }
    if wanted == key { return path }
    if wanted != pendingKey {
      pending?.cancel()
      pendingKey = wanted
      let first = path == nil
      pending = Task { [weak self] in
        if !first { try? await Task.sleep(for: .milliseconds(300)) }
        guard !Task.isCancelled else { return }
        await self?.make(wanted, control: control, canvasWidth: canvasWidth, canvasHeight: canvasHeight, fill: fill)
      }
    }
    return path
  }

  /// Frames, encodes and writes the picture away from the main actor (a third of a second for 2048 px, which the tab
  /// would spend frozen), then offers it.
  private func make(
    _ wanted: String, control: ControlStore, canvasWidth: Int, canvasHeight: Int, fill: MarginFill
  ) async {
    defer { if pendingKey == wanted { pendingKey = nil } }
    guard let render = control.framedStartImageRender(canvasWidth: canvasWidth, canvasHeight: canvasHeight, fill: fill)
    else { return }
    counter += 1
    let (number, startedIn) = (counter, epoch)
    let folder = folder
    let url = folder.appendingPathComponent("start-framed-\(counter).png")
    let written = await Task.detached(priority: .userInitiated) {
      guard let image = render(), let data = ControlStore.pngData(of: image) else { return false }
      try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      return (try? data.write(to: url, options: .atomic)) != nil
    }.value
    guard written else { return }
    // The start image went away meanwhile, or a picture started after this one is already on offer.
    guard epoch == startedIn, number > shown else {
      try? FileManager.default.removeItem(at: url)
      return
    }
    // A picture of a framing that has moved on since is offered all the same: while the framing keeps changing every
    // half second (a stepper, the wheel) no picture would ever be the last one, and the plug-ins would see nothing move
    // until it stops. The one of the framing as it is now follows.
    if let old = path { try? FileManager.default.removeItem(atPath: old) }
    path = url.path
    key = wanted
    shown = number
    onChange?()
  }

  private func reset() {
    pending?.cancel()
    pendingKey = nil
    epoch += 1
    if let old = path { try? FileManager.default.removeItem(atPath: old) }
    path = nil
    key = nil
  }
}
