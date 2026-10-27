import CoreGraphics
import DTHubPluginKit
import Foundation

/// The picture of the canvas or of the sphere view, observed by the two views that draw it.
@MainActor
final class PSPreview: ObservableObject {
  @Published var image: CGImage?
  /// How long the last frame took to draw, and from the request to the picture being there (milliseconds): shown in the sphere view's badge.
  var renderMillis = 0.0
  var latencyMillis = 0.0
}

/// Where the sphere view looks, as it is moved: an object of its own, so that looking around redraws only the sphere view and not every card of the tab.
/// The document gets the camera when the movement stops.
@MainActor
final class PSCameraBox: ObservableObject {
  @Published var camera = PSCamera()
}

/// The tab's state: the document of the open project and what the app last said about the model.
@MainActor
final class PSState: ObservableObject {
  /// Every change is saved in the project's folder; before the app says which project is open nothing is written.
  @Published var doc = PanoState() {
    didSet {
      // A camera set through the document (a project loaded, a test) is the live camera too.
      if !committingCamera, doc.camera != oldValue.camera { cameraBox.camera = doc.camera }
      persist()
    }
  }
  /// The live camera of the sphere view; `doc.camera` catches up when the movement stops (`flushSave`).
  let cameraBox = PSCameraBox()
  var camera: PSCamera { cameraBox.camera }
  private var cameraDirty = false
  private var committingCamera = false
  @Published private(set) var projectFolder: URL?
  /// The chosen model's file and the folder to exchange pictures through, from the last `context`.
  @Published var modelFile: String?
  private(set) var tempFolder = ""
  private var isLoading = false
  /// The pictures of the stickers, by sticker id (loaded from the project folder when first needed).
  let images = PSImageCache()
  /// The panorama as the canvas shows it, and what the pointer is doing to a sticker.
  /// Which renderer draws (Metal or CPU), for the badge of the sphere view.
  var rendererName: String { PSRendererFactory.make().backendName }
  var rendererLabel: String { PSRendererFactory.fallbackReason.map { "\(rendererName) (\($0))" } ?? rendererName }

  /// The picture the canvas shows lives in an object of its own, so that a new frame redraws only the view that shows it, not every card of the tab.
  let previewBox = PSPreview()
  var preview: CGImage? {
    get { previewBox.image }
    set { previewBox.image = newValue }
  }
  @Published private(set) var isDragging = false
  /// What the user should read after the last add or send (a bad file, a cropped photo…); nil when there is nothing.
  @Published var notice: String?
  /// What went wrong in the last «Improve prompt» or send, in the words to show.
  @Published var error: String?
  @Published var isImproving = false
  @Published var isSending = false
  /// The correction of the seam that is waiting for RUN (and running), and the button that proposed it.
  var seamSession: PSSeamSession?
  /// The panorama the correction in `seamSession` was made from (the newest result may have changed since).
  var seamSourcePath: String?
  /// Where DT Hub keeps the presets (the seam correction reads the model of its preset from there).
  var presetsFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/DT Hub/Presets", isDirectory: true)
  @Published var isSeamPrepared = false
  /// True after a send the app accepted: from then on the model of the preset it applied is checked (see `warning`).
  @Published var hasSent = false
  /// The description before the last «Improve prompt», for «Undo».
  @Published var previousDescription: String?
  var drag: PSDrag? {
    didSet {
      let dragging = drag != nil
      if isDragging != dragging { isDragging = dragging }
      if drag == nil { flushSave() }
    }
  }
  /// The next preview to draw: one render runs at a time and only the newest request waits, so a fast drag never piles up work.
  var pendingPreview: (job: @Sendable () throws -> CGImage, requested: ContinuousClock.Instant)?
  var previewLoopRunning = false
  var previewRenderCount = 0
  /// How a picture file's size is read (a test counts the calls) and what was read, so a redraw does not open the same file again.
  var imageSizeReader: (URL) -> (Int, Int)? = { PSCutout.pixelSize(of: $0).map { ($0.width, $0.height) } }
  private var sizeMemo: [String: (Int, Int)] = [:]
  /// A save held back: while a pointer drag goes on, or for a short while after the camera moved.
  private var saveWaiting = false
  private var saveTask: Task<Void, Never>?
  let italian: Bool
  /// The size the canvas pictures are drawn at (the ERP, and the 4:3 view from the camera).
  static let planeSize = CGSize(width: 1024, height: 512)
  static let sphereSize = CGSize(width: 1024, height: 768)
  /// The newest result of the project, from the app's context, and the picture read from its file.
  @Published private(set) var lastResultPath: String?
  @Published private(set) var resultImage: CGImage?
  /// The last picture extracted with the Cutout (kept in memory only: the actions need it, the memory in the state needs only the pose).
  @Published var cutoutImage: CGImage?
  /// Brings a picture file into the project folder (the real store; a test puts another here).
  var addPicture: (URL, URL) throws -> PSStickerAdded = { try PSStickerStore.add(contentsOf: $0, into: $1) }

  init(italian: Bool = L.systemIsItalian) { self.italian = italian }

  func text(_ key: L.Key) -> String { L.text(key, italian: italian) }
  func text(_ key: L.Key, _ args: CVarArg...) -> String { String(format: L.text(key, italian: italian), arguments: args) }

  /// True when the chosen model is a Base one (the LoRA works only with those); nil without a model.
  var modelIsBase: Bool? {
    guard let modelFile, !modelFile.isEmpty else { return nil }
    return modelFile.lowercased().contains("base")
  }

  func switchProject(folder: URL) {
    flushSave()
    isLoading = true
    projectFolder = folder
    doc = PanoState.load(from: folder)
    isLoading = false
    // What belonged to the project that was open stays with it.
    images.removeAll()
    drag = nil
    previousDescription = nil
    error = nil
    notice = nil
    hasSent = false
    preview = nil
    cutoutImage = nil
  }

  func apply(context: Data) {
    guard let context = try? JSONDecoder().decode(DTHubContext.self, from: context) else { return }
    modelFile = context.model
    tempFolder = context.tempFolder
    setLastResult(context.lastResult?.path)
  }

  /// The source the view really shows: the result only when there is a result to show.
  var effectiveSource: PSSource { doc.source == .result && resultImage != nil ? .result : .canvas }

  /// What is wrong with the result, in words (nil when there is none or it is fine): a file that cannot be read, or a picture that is not 2:1.
  var resultNotice: String? {
    guard lastResultPath != nil else { return nil }
    guard let image = resultImage else { return text(.resultUnreadable) }
    return abs(Double(image.width) / Double(image.height) - 2) > 0.04 ? text(.resultNotTwoToOne) : nil
  }

  private func setLastResult(_ path: String?) {
    // A result that was deleted or moved after it was loaded is no longer there to show.
    if let path, resultImage != nil, !FileManager.default.fileExists(atPath: path) { resultImage = nil }
    if path != lastResultPath || (path != nil && resultImage == nil) {
      lastResultPath = path
      resultImage = path.flatMap { PSResultLoader.load(URL(fileURLWithPath: $0)) }
    }
    // Without a result to show, the canvas is what the view shows.
    if resultImage == nil, doc.source == .result { mutate { $0.source = .canvas } }
  }

  func setView(_ mode: PSViewMode) { mutate { $0.viewMode = mode } }

  func setSource(_ source: PSSource) {
    guard source == .canvas || resultImage != nil else { return }
    mutate { $0.source = source }
  }

  func mutate(_ change: (inout PanoState) -> Void) {
    var copy = doc
    change(&copy)
    doc = copy
  }

  /// Every change is saved, except that a pointer drag saves once when it ends.
  private func persist() {
    guard !isLoading, projectFolder != nil else { return }
    if isDragging { saveWaiting = true } else { writeNow() }
  }

  /// Brings the document up to date with the live camera and writes what is held back, now.
  func flushSave() {
    saveTask?.cancel()
    saveTask = nil
    if cameraDirty {
      cameraDirty = false
      if doc.camera != cameraBox.camera {
        committingCamera = true
        var updated = doc
        updated.camera = cameraBox.camera
        doc = updated
        committingCamera = false
      }
    }
    if saveWaiting && !isDragging { writeNow() }
  }

  private func writeNow() {
    saveWaiting = false
    guard let projectFolder else { return }
    try? doc.save(to: projectFolder)
  }

  /// Moves the live camera (the sphere view redraws, nothing else does); the document and the file follow a moment after the last move, or when the
  /// drag that moves it ends.
  func setCamera(_ camera: PSCamera) {
    var clamped = camera
    clamped.clamp()
    cameraBox.camera = clamped
    // The new frame is asked for here, not when a view notices the change: one step less between the pointer and the picture.
    if doc.viewMode == .sphere { refreshPreview(scale: isDragging ? 0.5 : 1) }
    cameraDirty = true
    saveWaiting = true
    saveTask?.cancel()
    saveTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      self?.flushSave()
    }
  }

  /// The size of a picture file, read once; nil when the file is gone.
  func patchSize(_ url: URL) -> (Int, Int)? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    if let known = sizeMemo[url.path] { return known }
    guard let size = imageSizeReader(url) else { return nil }
    sizeMemo[url.path] = size
    return size
  }
}
