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
