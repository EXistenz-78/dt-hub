import DTHubPluginKit
import Foundation

/// The master prompt of "Advise" as a Markdown file (`Data/LoRAAdvisor/master-prompt.md`) and the user's own additions
/// in `custom/master-prompt.md` (a header `mode: replace` replaces the master prompt instead).
enum LAPrompts {
  static let masterPath = "master-prompt.md"

  static func folder(dataFolder: URL = LAStore.defaultFolder) -> DTHubPromptFolder {
    DTHubPromptFolder(folder: dataFolder)
  }

  /// At launch: writes the master prompt if it is missing or older than the built-in one, and makes `custom/`.
  static func install(dataFolder: URL = LAStore.defaultFolder) {
    folder(dataFolder: dataFolder).install([masterPath: EmbeddedData.masterPrompt])
  }

  static func system(italian: Bool, in folder: DTHubPromptFolder = folder()) -> String {
    let master = folder.base(masterPath, embedded: EmbeddedData.masterPrompt).file.body
    return folder.assemble(rules: master, family: "", extras: [], customName: masterPath, label: "LoRA Advisor")
      .replacingOccurrences(of: "{max}", with: String(LAAdvice.most))
      .replacingOccurrences(of: "{language}", with: L.text(.languageName, italian: italian))
  }

  /// Why the master prompt file is not used; empty when all is well.
  static func problems(in folder: DTHubPromptFolder = folder()) -> [String] {
    folder.base(masterPath, embedded: EmbeddedData.masterPrompt).problem.map { [$0] } ?? []
  }
}
