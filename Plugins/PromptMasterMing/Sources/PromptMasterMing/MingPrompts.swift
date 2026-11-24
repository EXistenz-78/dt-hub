import DTHubPluginKit
import Foundation

/// I prompt del plug-in come file Markdown (`Data/prompt-master-ming/`): il master prompt di «Scrivi con LLM»
/// (`master-prompt.md`) e quello di «Componi con LLM» (`compose-prompt.md`), con quelli dell'utente in `custom/`.
/// Per comporre vale prima il Family prompt Ming che l'app manda con il contesto (quello che l'utente vede e cambia nell'app);
/// `compose-prompt.md` ne è la copia per quando l'app non lo manda.
enum MingPrompts {
  static let masterPath = "master-prompt.md"
  static let composePath = "compose-prompt.md"

  static func folder(dataFolder: URL = DataSource.defaultFolder) -> DTHubPromptFolder {
    DTHubPromptFolder(folder: dataFolder.appendingPathComponent("prompt-master-ming", isDirectory: true))
  }

  static func install(dataFolder: URL = DataSource.defaultFolder) {
    folder(dataFolder: dataFolder).install([masterPath: EmbeddedData.masterPrompt, composePath: EmbeddedData.composePrompt])
  }

  static func system(in folder: DTHubPromptFolder = folder()) -> String {
    let master = folder.base(masterPath, embedded: EmbeddedData.masterPrompt).file.body
    return folder.assemble(rules: master, family: "", extras: [], customName: masterPath, label: "Ming-Image")
  }

  /// Il prompt di composizione: il Family prompt dell'app se c'è, altrimenti il file; poi quello dell'utente.
  static func composeSystem(familyPrompt: String?, in folder: DTHubPromptFolder = folder()) -> String {
    let base: String
    if let familyPrompt, !familyPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      base = familyPrompt + "\n\nThis request always asks for the structured JSON design (never the plain-prose cases)."
    } else {
      base = folder.base(composePath, embedded: EmbeddedData.composePrompt).file.body
    }
    return folder.assemble(rules: base, family: "", extras: [], customName: composePath, label: "Ming-Image")
  }

  static func problems(in folder: DTHubPromptFolder = folder()) -> [String] {
    [masterPath: EmbeddedData.masterPrompt, composePath: EmbeddedData.composePrompt].sorted { $0.key < $1.key }
      .compactMap { folder.base($0.key, embedded: $0.value).problem }
  }
}
