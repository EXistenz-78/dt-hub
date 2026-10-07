import DTHubPluginKit
import Foundation

/// What the plug-in remembers between runs: the switch and the model. The picture and the name start empty.
struct CSSettings: Codable, Equatable {
  var useStatic = false
  var model: String?
}

/// `settings.json` in the plug-in's data folder (next to the two text files).
struct CSSettingsStore {
  var folder: URL

  private var fileURL: URL { folder.appendingPathComponent("settings.json") }

  /// Lenient: a missing or unreadable file gives the defaults.
  func load() -> CSSettings {
    guard let data = try? Data(contentsOf: fileURL), let settings = try? JSONDecoder().decode(CSSettings.self, from: data)
    else { return CSSettings() }
    return settings
  }

  func save(_ settings: CSSettings) {
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    if let data = try? JSONEncoder().encode(settings) { try? data.write(to: fileURL, options: .atomic) }
  }
}

/// The state of the tab.
@MainActor
final class CSState: ObservableObject {
  @Published var active = false
  @Published var imagePath: String?
  @Published var name = ""
  @Published var useStatic: Bool { didSet { saveSettings() } }
  /// The name of the model the user chose; may be one the app no longer lists (see `resolvedModel`).
  @Published var selectedModel: String? { didSet { saveSettings() } }
  @Published var status = ""
  @Published private(set) var busy = false
  @Published private(set) var languageModels: [DTHubLanguageModel] = []
  private(set) var tempFolder: String?
  private(set) var family: String?
  private let store: CSSettingsStore

  init(store: CSSettingsStore) {
    self.store = store
    let settings = store.load()
    useStatic = settings.useStatic
    selectedModel = settings.model
  }

  /// A picture is mandatory, so only the models that read pictures are offered.
  var visionModels: [DTHubLanguageModel] { languageModels.filter(\.supportsImages) }

  /// The chosen model if it is still offered, otherwise the first one with vision.
  var resolvedModel: DTHubLanguageModel? {
    visionModels.first { $0.name == selectedModel } ?? visionModels.first
  }

  var job: CSJob {
    CSJob(imagePath: imagePath, name: name, useStatic: useStatic, model: resolvedModel, tempFolder: tempFolder)
  }

  func update(from context: DTHubContext) {
    tempFolder = context.tempFolder
    family = context.family
    languageModels = context.languageModels ?? []
  }

  /// False when a preparation is already running.
  func beginPrepare() -> Bool {
    guard !busy else { return false }
    busy = true
    return true
  }

  func endPrepare(status: String) {
    self.status = status
    busy = false
  }

  private func saveSettings() {
    store.save(CSSettings(useStatic: useStatic, model: selectedModel))
  }
}
