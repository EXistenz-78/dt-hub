import Foundation

/// The three kinds of sheet the plug-in prepares.
enum CSSheetKind: String, CaseIterable, Codable {
  /// The full character design sheet: views, poses, silhouettes, expressions, details.
  case base
  /// Twelve expressions on a 4×3 grid.
  case expressions
  /// Ten dynamic poses on a 5×2 grid.
  case poses
}

/// The text files of the plug-in: for each kind of sheet, the master prompt (for the language model) and the static
/// prompt (no model). The plug-in carries its own copy (`CSBuiltIn`); a file of the same name in the user's data folder
/// wins, so the texts can be edited at any time.
enum CSTemplateFile: String, CaseIterable {
  case master = "master-prompt.txt"
  case staticPrompt = "static-prompt.txt"
  case masterExpressions = "master-prompt-expressions.txt"
  case staticExpressions = "static-prompt-expressions.txt"
  case masterPoses = "master-prompt-poses.txt"
  case staticPoses = "static-prompt-poses.txt"

  static func of(useStatic: Bool, kind: CSSheetKind) -> CSTemplateFile {
    switch (kind, useStatic) {
    case (.base, false): return .master
    case (.base, true): return .staticPrompt
    case (.expressions, false): return .masterExpressions
    case (.expressions, true): return .staticExpressions
    case (.poses, false): return .masterPoses
    case (.poses, true): return .staticPoses
    }
  }
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

  /// The text to use: the file of the folder when it has text, otherwise the one built into the plug-in. A user who
  /// wants other words puts a file of the same name in the folder (see `seedMissing`).
  static func resolved(_ file: CSTemplateFile, from folder: URL) -> String {
    if case .success(let text) = load(file, from: folder) { return text }
    return CSBuiltIn.text(for: file)
  }

  /// Writes the built-in text of every file the folder does not have yet (creating the folder), so there is
  /// something to edit; a file that is already there is never touched.
  static func seedMissing(in folder: URL) {
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for file in CSTemplateFile.allCases {
      let url = folder.appendingPathComponent(file.rawValue)
      guard !FileManager.default.fileExists(atPath: url.path) else { continue }
      try? (CSBuiltIn.text(for: file) + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
  }

  /// Every `{{name}}` becomes the name, in one pass (a name that looks like the placeholder stays as written).
  static func fill(_ text: String, name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.replacingOccurrences(of: placeholder, with: trimmed.isEmpty ? fallbackName : trimmed)
  }
}
