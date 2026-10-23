import DTHubPluginKit
import Foundation

/// The master prompt of the plug-in as a Markdown file (`Data/prompt-master-moss/master-prompt.md`) e quello dell'utente in
/// `custom/master-prompt.md`. Un prompt specialistico, solo per MOSS: non passa dai Family prompt dell'app.
enum MossPrompts {
  static let masterPath = "master-prompt.md"

  static func folder(dataFolder: URL = DataSource.defaultFolder) -> DTHubPromptFolder {
    DTHubPromptFolder(folder: dataFolder.appendingPathComponent("prompt-master-moss", isDirectory: true))
  }

  /// At launch: writes the master prompt if it is missing or older than the built-in one, and makes `custom/`.
  static func install(dataFolder: URL = DataSource.defaultFolder) {
    folder(dataFolder: dataFolder).install([masterPath: EmbeddedData.masterPrompt])
  }

  /// The system prompt: the master prompt (the file when valid and not older, the built-in copy otherwise), then the
  /// user's own after the priority line (`mode: replace` takes the master's place).
  static func system(in folder: DTHubPromptFolder = folder()) -> String {
    let master = folder.base(masterPath, embedded: EmbeddedData.masterPrompt).file.body
    return folder.assemble(rules: master, family: "", extras: [], customName: masterPath, label: "MOSS Image")
  }

  /// Why the master prompt file is not used; empty when all is well.
  static func problems(in folder: DTHubPromptFolder = folder()) -> [String] {
    folder.base(masterPath, embedded: EmbeddedData.masterPrompt).problem.map { [$0] } ?? []
  }
}
