import Foundation

/// The two text files the plug-in reads: the master prompt (for the language model) and the static prompt (no model).
/// They live outside the repository, in the user's data folder, and can be edited at any time.
enum CSTemplateFile: String, CaseIterable {
  case master = "master-prompt.txt"
  case staticPrompt = "static-prompt.txt"
}

enum CSTemplateError: Error, Equatable {
  case missing(CSTemplateFile)
  case empty(CSTemplateFile)
}

enum CSTemplates {
  /// Used when the name field is empty.
  static let fallbackName = "CHARACTER"
  static let placeholder = "{{name}}"

  /// ~/Library/Application Support/DT Hub/Data/CharacterSheet (next to Prompt Master's data files).
  static var defaultFolder: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true)
      .appendingPathComponent("Data", isDirectory: true)
      .appendingPathComponent("CharacterSheet", isDirectory: true)
  }

  /// The text of a file without outer whitespace.
  static func load(_ file: CSTemplateFile, from folder: URL) -> Result<String, CSTemplateError> {
    guard let text = try? String(contentsOf: folder.appendingPathComponent(file.rawValue), encoding: .utf8) else {
      return .failure(.missing(file))
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? .failure(.empty(file)) : .success(trimmed)
  }

  /// Every `{{name}}` becomes the name, in one pass (a name that looks like the placeholder stays as written).
  static func fill(_ text: String, name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.replacingOccurrences(of: placeholder, with: trimmed.isEmpty ? fallbackName : trimmed)
  }
}
