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
  /// The description before the last «Improve prompt», for «Undo».
  @Published var previousDescription: String?
  var drag: PSDrag? { didSet { isDragging = drag != nil } }
  var previewGeneration = 0
  let italian: Bool
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
  }

  func apply(context: Data) {
    guard let context = try? JSONDecoder().decode(DTHubContext.self, from: context) else { return }
    modelFile = context.model
    tempFolder = context.tempFolder
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
