import AppKit
import SwiftUI

/// What the tab shows and edits: the mode and the view (remembered per project), whether the pipeline is proposed, the
/// picture on show and its seam check.
@MainActor
final class SPState: ObservableObject {
  static let customServerWarning =
    "Seamless Pattern needs DT Hub's own server (Preferences › Draw Things: use the included server)."

  private var store: SPStore
  private var isRestoring = false
  private var loadCount = 0
  private var renderCount = 0
  /// The `lastResult` of the last context: a new one replaces what is on show, the same one does not.
  private var lastSeenResult: String?

  @Published private(set) var mode: SPMode
  @Published var view: SPView {
    didSet {
      persist()
      if view != oldValue { Task { await refreshPreview() } }
    }
  }
  @Published private(set) var isPrepared = false
  @Published private(set) var customServer: Bool?
  @Published private(set) var family: String?
  /// The app's problem with the last proposal (or "no answer"); nil when it took it.
  @Published private(set) var notice: String?
  /// The file on show: the newest result, or an image dropped on the preview.
  @Published private(set) var source: URL?
  @Published private(set) var image: CGImage?
  @Published private(set) var seam: (leftRight: SPSeamResult, upDown: SPSeamResult)?
  @Published private(set) var previewImage: NSImage?
  @Published var active = false
  @Published var status = ""

  /// Sends a `contribute` message and returns the app's answer (the plug-in connects it to the host).
  var send: @MainActor (Data) async -> [String: Any]? = { _ in nil }

  init(store: SPStore = SPStore()) {
    self.store = store
    let session = store.load() ?? SPSession()
    mode = session.mode
    view = session.view
  }

  // MARK: What can be done

  var familySupported: Bool { family.map(SeamlessPatternPlugin.families.contains) ?? true }

  /// The custom server is there (an app that does not say counts as not) and the family is one it tiles.
  var canPrepare: Bool { customServer == true && familySupported }

  /// Shown instead of the whole tab when the server is not the custom one.
  var warning: String? { customServer == true ? nil : Self.customServerWarning }

  /// Why the pipeline cannot be proposed now (what the tab shows, and what an agent is told); nil when it can.
  var prepareRefusal: String? {
    if customServer != true { return Self.customServerWarning }
    return familySupported ? nil : L.unsupportedFamily
  }

  // MARK: Pipeline

  func prepare() async {
    guard canPrepare else { return }
    notice = nil
    let answer = await send(SPSender.prepare(mode: mode))
    guard let answer else {
      isPrepared = false
      notice = L.notAnswered
      return
    }
    if answer["type"] as? String == "error" {
      isPrepared = false
      notice = answer["text"] as? String ?? L.notAnswered
      return
    }
    let problems = (answer["problems"] as? [String]) ?? []
    isPrepared = problems.isEmpty
    notice = problems.isEmpty ? nil : problems.joined(separator: " ")
  }

  /// Takes the pipeline back. Only a clean answer of the app clears it: a refusal (a pipeline is running), an error or no
  /// answer leaves it prepared and its text becomes the notice.
  func stop() async {
    let answer = await send(SPSender.stop())
    guard let answer else {
      notice = L.notAnswered
      return
    }
    if answer["type"] as? String == "error" {
      notice = answer["text"] as? String ?? L.notAnswered
      return
    }
    let problems = (answer["problems"] as? [String]) ?? []
    guard problems.isEmpty else {
      notice = problems.joined(separator: " ")
      return
    }
    notice = nil
    isPrepared = false
  }

  /// A new mode while the pipeline is proposed proposes it again with the new one.
  func setMode(_ new: SPMode) async {
    guard new != mode else { return }
    mode = new
    persist()
    if isPrepared { await prepare() }
  }

  /// The app's context: the family, whether the server is the custom one, the newest result. A pipeline that cannot work any
  /// more (the server is not the custom one, or the family is not tiled) is taken back.
  func applyContext(family: String?, customServer: Bool?, lastResultPath: String?) async {
    self.family = family
    self.customServer = customServer
    if isPrepared && !canPrepare { await stop() }
    if lastResultPath != lastSeenResult {
      lastSeenResult = lastResultPath
      if let lastResultPath { await show(url: URL(fileURLWithPath: lastResultPath)) }
    }
  }

  /// The plug-in was switched off: the app has already taken its pipeline back, so nothing is sent.
  func deactivate() {
    isPrepared = false
  }

  // MARK: Picture

  /// Shows a file (a result, or an image dropped on the preview) and checks its seam.
  func show(url: URL) async {
    loadCount += 1
    let ticket = loadCount
    let loaded = await Task.detached(priority: .userInitiated) { () -> (CGImage, SPSeamResult, SPSeamResult)? in
      guard let image = SPPNG.load(url) else { return nil }
      let seam = SPSeam.check(image)
      return (image, seam.leftRight, seam.upDown)
    }.value
    guard ticket == loadCount, let loaded else { return }
    source = url
    image = loaded.0
    seam = (loaded.1, loaded.2)
    await refreshPreview()
  }

  private func refreshPreview() async {
    renderCount += 1
    let ticket = renderCount
    guard let image else {
      previewImage = nil
      return
    }
    let view = view
    let rendered = await Task.detached(priority: .userInitiated) { SPTileView.render(image, view: view) }.value
    guard ticket == renderCount else { return }
    previewImage = rendered.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
  }

  // MARK: Per project

  /// The app opened a project: the tab shows its mode and view (a project without a state starts with the defaults).
  func switchProject(folder: URL) {
    store.folder = folder
    let session = store.load() ?? SPSession()
    isRestoring = true
    mode = session.mode
    view = session.view
    isRestoring = false
  }

  private func persist() {
    guard !isRestoring else { return }
    store.save(SPSession(mode: mode, view: view))
  }

  // MARK: Seam line

  /// "PASS" / "WARN" / "FAIL" / "N/A" for a direction the run asked for; for the other one only the number.
  static func seamText(_ result: SPSeamResult, judged: Bool) -> String {
    if result.status == .notApplicable { return "N/A" }
    if !judged { return result.ratio.map { String(format: "%.2f", $0) } ?? "–" }
    switch result.status {
    case .pass: return "PASS"
    case .warn: return "WARN"
    case .fail: return "FAIL"
    case .notApplicable: return "N/A"
    }
  }

  // MARK: Files

  func savePNG() {
    guard let image, let png = SPPNG.data(from: image) else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.nameFieldStringValue = (source?.deletingPathExtension().lastPathComponent ?? "pattern") + "-tile.png"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    status = (try? png.write(to: url, options: .atomic)) != nil ? L.saved : L.saveFailed
  }

  func showInFinder() {
    guard let source else { return }
    NSWorkspace.shared.activateFileViewerSelecting([source])
  }
}
