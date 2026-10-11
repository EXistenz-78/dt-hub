import DTHubPluginKit
import Foundation

/// The master prompt of the plug-in as a Markdown file (`Data/prompt-master-i4/master-prompt.md`) and the user's own in
/// `custom/master-prompt.md`. A specialist prompt, only for Ideogram 4: it does not go through the app's Family prompts.
enum I4Prompts {
  static let masterPath = "master-prompt.md"

  static func folder(dataFolder: URL = DataSource.defaultFolder) -> DTHubPromptFolder {
    DTHubPromptFolder(folder: dataFolder.appendingPathComponent("prompt-master-i4", isDirectory: true))
  }

  /// At launch: writes the master prompt if it is missing or older than the built-in one, and makes `custom/`.
  static func install(dataFolder: URL = DataSource.defaultFolder) {
    folder(dataFolder: dataFolder).install([masterPath: EmbeddedData.masterPrompt])
  }

  /// The system prompt: the master prompt (the file when valid and not older, the built-in copy otherwise), then the
  /// user's own after the priority line (`mode: replace` takes the master's place).
  static func system(in folder: DTHubPromptFolder = folder()) -> String {
    let master = folder.base(masterPath, embedded: EmbeddedData.masterPrompt).file.body
    return folder.assemble(rules: master, family: "", extras: [], customName: masterPath, label: "Ideogram 4")
  }

  /// Why the master prompt file is not used; empty when all is well.
  static func problems(in folder: DTHubPromptFolder = folder()) -> [String] {
    folder.base(masterPath, embedded: EmbeddedData.masterPrompt).problem.map { [$0] } ?? []
  }
}
