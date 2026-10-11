import Foundation

/// A plug-in's folder of prompt files (`…/Data/<plug-in>/`): the base files (`rules/…`), written from the copies built
/// into the plug-in, and the user's own in `custom/`. The same rules as the app's own prompts (spec «Prompt modulari»):
/// a file wins when it is valid and not older than the built-in copy; the user's file goes last and wins on conflict.
public struct DTHubPromptFolder: Sendable {
  public let folder: URL

  public init(folder: URL) {
    self.folder = folder
  }

  public static let priorityLine = "In case of conflict, the instructions below take precedence over those above."

  private func read(_ path: String) -> String? {
    try? String(contentsOf: folder.appendingPathComponent(path), encoding: .utf8)
  }

  /// The file at `path` when it is valid and not older than `embedded`; the built-in copy otherwise, with the reason.
  public func base(_ path: String, embedded: String) -> (file: DTHubPromptFile, problem: String?) {
    let builtIn = DTHubPromptFile.parse(embedded)
    guard let text = read(path) else { return (builtIn, nil) }
    let file = DTHubPromptFile.parse(text)
    if !file.isValid { return (builtIn, "\(path): the header is not valid; the built-in copy is used.") }
    if file.version < builtIn.version {
      return (builtIn, "\(path): version \(file.version) is older than the built-in \(builtIn.version); the built-in copy is used.")
    }
    return (file, nil)
  }

  /// `custom/<name>`: nil when absent or with nothing in it.
  public func custom(_ name: String) -> (body: String, replaces: Bool)? {
    guard let text = read("custom/\(name)") else { return nil }
    let file = DTHubPromptFile.parse(text)
    let body = file.body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty else { return nil }
    return (body, file.header["mode"] == "replace")
  }

  /// Writes the files (path → built-in text) that are missing, not valid or older than the built-in copy (the old one is
  /// kept as `<name>.bak`) and makes `custom/`. A folder that cannot be written is no error.
  public func install(_ files: [String: String]) {
    let manager = FileManager.default
    for (path, embedded) in files {
      let url = folder.appendingPathComponent(path)
      try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      if let text = try? String(contentsOf: url, encoding: .utf8) {
        let file = DTHubPromptFile.parse(text)
        if file.isValid && file.version >= DTHubPromptFile.parse(embedded).version { continue }
        let backup = url.appendingPathExtension("bak")
        try? manager.removeItem(at: backup)
        try? manager.copyItem(at: url, to: backup)
      }
      try? embedded.write(to: url, atomically: true, encoding: .utf8)
    }
    try? manager.createDirectory(at: folder.appendingPathComponent("custom"), withIntermediateDirectories: true)
  }

  /// Rules, the family's text (may be empty) and the extras, then the user's file `custom/<customName>` (added after the priority line,
  /// or, with `mode: replace`, in place of the rules). `{label}` is resolved in the user's replacing text.
  public func assemble(rules: String, family: String, extras: [String], customName: String, label: String) -> String {
    var first = rules.trimmingCharacters(in: .whitespacesAndNewlines)
    var parts: [String] = []
    var appended: [String] = []
    if let mine = custom(customName) {
      if mine.replaces {
        first = mine.body.replacingOccurrences(of: "{label}", with: label)
      } else {
        appended.append(Self.priorityLine + "\n\n" + mine.body)
      }
    }
    parts.append(first)
    parts.append(family.trimmingCharacters(in: .whitespacesAndNewlines))
    parts += extras.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    return (parts + appended).filter { !$0.isEmpty }.joined(separator: "\n\n")
  }
}
