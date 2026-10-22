import DTHubPluginKit
import Foundation

/// Il master prompt del plug-in come file Markdown (`Data/prompt-master-flux3-editing/master-prompt.md`) e quello dell'utente in
/// `custom/master-prompt.md`. Un prompt specialistico, solo per questo plug-in: non passa dai Family prompt dell'app.
enum EditPrompts {
  static let masterPath = "master-prompt.md"
  static let folderName = "prompt-master-flux3-editing"

  static var defaultDataFolder: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true).appendingPathComponent("Data", isDirectory: true)
  }

  /// Le opzioni dell'LLM (le stesse di Prompt Master F3).
  static let options = DTHubLLMOptions(temperature: 0.6, maxTokens: 4096, thinking: false, timeout: 600)

  static func folder(dataFolder: URL = defaultDataFolder) -> DTHubPromptFolder {
    DTHubPromptFolder(folder: dataFolder.appendingPathComponent(folderName, isDirectory: true))
  }

  /// All'avvio: scrive il master prompt se manca o è più vecchio di quello incorporato, e crea `custom/`.
  static func install(dataFolder: URL = defaultDataFolder) {
    folder(dataFolder: dataFolder).install([masterPath: EmbeddedData.masterPrompt])
  }

  /// Il system prompt: il master prompt (il file se valido e non più vecchio, la copia incorporata altrimenti), poi quello
  /// dell'utente dopo la riga di priorità.
  static func system(in folder: DTHubPromptFolder = folder()) -> String {
    let master = folder.base(masterPath, embedded: EmbeddedData.masterPrompt).file.body
    return folder.assemble(rules: master, family: "", extras: [], customName: masterPath, label: "FLUX.3")
  }

  /// Perché il file del master prompt non si usa; vuoto se va tutto bene.
  static func problems(in folder: DTHubPromptFolder = folder()) -> [String] {
    folder.base(masterPath, embedded: EmbeddedData.masterPrompt).problem.map { [$0] } ?? []
  }
}
