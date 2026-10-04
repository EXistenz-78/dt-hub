import AppKit
import SwiftUI

/// What the tab shows and edits. The lights and the two boxes are remembered (`SLRStore`).
@MainActor
final class SLRState: ObservableObject {
  static let previewSize = 220

  private let store: SLRStore
  private var renderTask: Task<Void, Never>?

  @Published var lights: [LightParams] { didSet { persist() } }
  @Published var expanded: [UUID: Bool] { didSet { persist() } }
  @Published var overcast: Bool { didSet { persist() } }
  @Published var saveToDesktop: Bool { didSet { persist() } }
  @Published var previewImage: NSImage?
  @Published var status = ""
  @Published var isSending = false
  @Published var active = false
  /// The folder the app lends for exchanging pictures (from the `context` message).
  var tempFolder: String?

  init(store: SLRStore = SLRStore()) {
    self.store = store
    let session = store.load() ?? .initial()
    lights = session.lights
    expanded = session.expanded
    overcast = session.overcast
    saveToDesktop = session.saveToDesktop
    scheduleRender()
  }

  var canAddLight: Bool { lights.count < SLRSession.maxLights }

  func addLight() {
    guard canAddLight else { return }
    let light = LightParams.makeDefault(index: lights.count)
    lights.append(light)
    expanded[light.id] = true
    scheduleRender()
  }

  func removeLight(_ id: UUID) {
    guard lights.count > 1 else { return }
    lights.removeAll { $0.id == id }
    expanded.removeValue(forKey: id)
    scheduleRender()
  }

  func lightChanged() { scheduleRender() }

  /// The preview, ~60 ms after the last movement of a slider.
  private func scheduleRender() {
    renderTask?.cancel()
    let snapshot = lights
    renderTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 60_000_000)
      guard !Task.isCancelled else { return }
      let size = Self.previewSize
      let pixels = await Task.detached(priority: .userInitiated) {
        SphereRenderer.render(width: size, height: size, lights: snapshot, shadowSampleCount: 10)
      }.value
      guard !Task.isCancelled else { return }
      self?.previewImage = SphereRenderer.nsImage(fromRGB8: pixels, width: size, height: size)
    }
  }

  private func persist() {
    store.save(SLRSession(lights: lights, expanded: expanded, overcast: overcast, saveToDesktop: saveToDesktop))
  }
}
