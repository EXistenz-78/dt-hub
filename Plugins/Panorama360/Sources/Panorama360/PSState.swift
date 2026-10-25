import CoreGraphics
import DTHubPluginKit
import Foundation

/// The tab's state: the document of the open project and what the app last said about the model.
@MainActor
final class PSState: ObservableObject {
  /// Every change is saved in the project's folder; before the app says which project is open nothing is written.
  @Published var doc = PanoState() {
    didSet { persist() }
  }
  @Published private(set) var projectFolder: URL?
  /// The chosen model's file and the folder to exchange pictures through, from the last `context`.
  @Published private(set) var modelFile: String?
  private(set) var tempFolder = ""
  private var isLoading = false
  /// The pictures of the stickers, by sticker id (loaded from the project folder when first needed).
  let images = PSImageCache()
  /// The panorama as the canvas shows it, and what the pointer is doing to a sticker.
  @Published var preview: CGImage?
  @Published private(set) var isDragging = false
  /// What the user should read after the last add or send (a bad file, a cropped photo…); nil when there is nothing.
  @Published var notice: String?
  /// What went wrong in the last «Improve prompt» or send, in the words to show.
  @Published var error: String?
  @Published var isImproving = false
  @Published var isSending = false
  /// True after a send the app accepted: from then on the model of the preset it applied is checked (see `warning`).
  @Published var hasSent = false
  /// The description before the last «Improve prompt», for «Undo».
  @Published var previousDescription: String?
  var drag: PSDrag? { didSet { isDragging = drag != nil } }
  var previewGeneration = 0
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

  private func persist() {
    guard !isLoading, let projectFolder else { return }
    try? doc.save(to: projectFolder)
  }
}
