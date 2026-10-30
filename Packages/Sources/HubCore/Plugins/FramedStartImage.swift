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
        self?.make(wanted, control: control, canvasWidth: canvasWidth, canvasHeight: canvasHeight, fill: fill)
      }
    }
    return path
  }

  private func make(_ wanted: String, control: ControlStore, canvasWidth: Int, canvasHeight: Int, fill: MarginFill) {
    defer { if pendingKey == wanted { pendingKey = nil } }
    guard let image = control.framedStartImage(canvasWidth: canvasWidth, canvasHeight: canvasHeight, fill: fill),
      let data = ControlStore.pngData(of: image)
    else { return }
    counter += 1
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("start-framed-\(counter).png")
    guard (try? data.write(to: url, options: .atomic)) != nil else { return }
    if let old = path { try? FileManager.default.removeItem(atPath: old) }
    path = url.path
    key = wanted
    onChange?()
  }

  private func reset() {
    pending?.cancel()
    pendingKey = nil
    if let old = path { try? FileManager.default.removeItem(atPath: old) }
    path = nil
    key = nil
  }
}
