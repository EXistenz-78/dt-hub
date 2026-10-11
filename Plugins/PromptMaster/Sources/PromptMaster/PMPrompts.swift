import DTHubPluginKit
import Foundation

/// The plug-in's own prompt files (`Data/prompt-master/`): the Rules of the task (`rules/compose.md`, and
/// `compose-tags.md` for the families written in tags) and the user's in `custom/`. The family's text comes from the app.
enum PMPrompts {
  static let rulesFiles: [String: String] = [
    "rules/compose.md": EmbeddedPrompts.compose, "rules/compose-tags.md": EmbeddedPrompts.composeTags,
  ]

  static func folder(dataFolder: URL = DataSource.defaultFolder) -> DTHubPromptFolder {
    DTHubPromptFolder(folder: dataFolder.appendingPathComponent(PMData.pluginFolderName, isDirectory: true))
  }

  /// At launch: writes the Rules that are missing or older, and makes `custom/`.
  static func install(dataFolder: URL = DataSource.defaultFolder) {
    folder(dataFolder: dataFolder).install(rulesFiles)
  }

  /// The Rules of the task for a family, `{label}` resolved: the file when valid, the built-in copy otherwise.
  static func rules(tags: Bool, in folder: DTHubPromptFolder, label: String) -> String {
    let path = tags ? "rules/compose-tags.md" : "rules/compose.md"
    let embedded = rulesFiles[path] ?? ""
    return folder.base(path, embedded: embedded).file.resolved(["label": label])
  }

  /// Why a Rules file is not used (a header that does not read, an older version); empty when all is well.
  static func problems(in folder: DTHubPromptFolder) -> [String] {
    rulesFiles.compactMap { folder.base($0.key, embedded: $0.value).problem }.sorted()
  }
}
