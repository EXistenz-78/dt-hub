import CoreGraphics
import DTHubPluginKit
import Foundation

typealias PFContribute = @MainActor ([String: Any]) async -> [String: Any]?

/// The tab's state: the document of the open project and what the app last said about the model and the results.
@MainActor
final class PFState: ObservableObject {
  /// Every change is saved in the project's folder; before the app says which project is open nothing is written.
  @Published var doc = PanoState() { didSet { persist() } }
  @Published private(set) var projectFolder: URL?
  /// The chosen model's file and the folder to exchange pictures through, from the last `context`.
  @Published var modelFile: String?
  private(set) var tempFolder = ""
  /// What the user should read after the last action; `error` is what went wrong.
  @Published var notice: String?
  @Published var error: String?
  @Published var isSending = false
  @Published var isImproving = false
  /// The description before the last «Improve prompt», for «Undo».
  @Published var previousDescription: String?
  /// The newest result of the project, from the app's context.
  @Published var lastResultPath: String?
  /// The run that is waiting for RUN (and running).
  var session: PFSession?
  /// Where DT Hub keeps the presets (the model of a preset is read from there for the note after a send).
  var presetsFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/DT Hub/Presets", isDirectory: true)
  /// Brings a picture file into the project folder (the real store; a test puts another here).
  var addPicture: (URL, URL) throws -> PFImage = { try PFImageStore.add(contentsOf: $0, into: $1) }
  let italian: Bool
  private var isLoading = false

  init(italian: Bool = L.systemIsItalian) { self.italian = italian }

  func text(_ key: L.Key) -> String { L.text(key, italian: italian) }
  func text(_ key: L.Key, _ args: CVarArg...) -> String { String(format: L.text(key, italian: italian), arguments: args) }

  /// Where the plug-in puts the files DT Hub reads (references, squares, results).
  var exchangeFolder: URL {
    (tempFolder.isEmpty ? FileManager.default.temporaryDirectory : URL(fileURLWithPath: tempFolder, isDirectory: true))
      .appendingPathComponent("pano-360-f3", isDirectory: true)
  }

  /// The pictures that are on, in order: the ones sent and numbered `<image 1>`, `<image 2>`…
  var visibleImages: [PFImage] { doc.images.filter(\.visible) }

  var canSend: Bool { projectFolder != nil && !visibleImages.isEmpty && !isSending }

  func mutate(_ change: (inout PanoState) -> Void) {
    var copy = doc
    change(&copy)
    doc = copy
  }

  func switchProject(folder: URL) {
    isLoading = true
    projectFolder = folder
    doc = PanoState.load(from: folder)
    isLoading = false
    previousDescription = nil
    error = nil
    notice = nil
    session = nil
  }

  func apply(context: Data) {
    guard let context = try? JSONDecoder().decode(DTHubContext.self, from: context) else { return }
    modelFile = context.model
    tempFolder = context.tempFolder
    lastResultPath = context.lastResult?.path
  }

  private func persist() {
    guard !isLoading, let projectFolder else { return }
    try? doc.save(to: projectFolder)
  }

  // MARK: pictures

  func imageURL(_ image: PFImage) -> URL? { projectFolder?.appendingPathComponent(image.file) }

  /// Brings pictures into the project, in the order given; one that cannot be read says so and changes nothing else.
  func addImages(_ urls: [URL]) {
    error = nil
    guard let projectFolder else {
      error = text(.openProjectFirst)
      return
    }
    for url in urls {
      do {
        let added = try addPicture(url, projectFolder)
        mutate { $0.images.append(added) }
      } catch {
        self.error = text(.unreadableFile, url.lastPathComponent)
      }
    }
  }

  /// Moves the pictures at `source` so that they come before the one that is at index `destination` now (as SwiftUI's `move(fromOffsets:toOffset:)`).
  func move(from source: IndexSet, to destination: Int) {
    let moving = source.sorted().map { doc.images[$0] }
    var rest = doc.images.enumerated().filter { !source.contains($0.offset) }.map(\.element)
    rest.insert(contentsOf: moving, at: destination - source.filter { $0 < destination }.count)
    mutate { $0.images = rest }
  }

  /// A row dropped on another one: it goes before it.
  func moveImage(_ id: UUID, before target: UUID) {
    guard id != target, let from = doc.images.firstIndex(where: { $0.id == id }), let to = doc.images.firstIndex(where: { $0.id == target }) else { return }
    move(from: IndexSet(integer: from), to: to)
  }

  func toggleVisible(_ id: UUID) {
    mutate { state in
      if let index = state.images.firstIndex(where: { $0.id == id }) { state.images[index].visible.toggle() }
    }
  }

  func remove(_ id: UUID) {
    guard let image = doc.images.first(where: { $0.id == id }) else { return }
    if let url = imageURL(image) { try? FileManager.default.removeItem(at: url) }
    mutate { $0.images.removeAll { $0.id == id } }
  }

  func sizeUp() { if let next = PFSizes.larger(doc.size) { mutate { $0.size = next } } }
  func sizeDown() { if let next = PFSizes.smaller(doc.size) { mutate { $0.size = next } } }
}
