import Foundation

/// What a prompt is asked to do (the Rules prompt depends on it).
public enum PromptTask: String, Sendable, CaseIterable {
  case enhance, describe
}

/// One family of image models, as the Family prompt file describes it.
public struct FamilyPrompt: Equatable, Sendable {
  public let id: String
  public let label: String
  /// The family reads a negative prompt (the answer is a JSON object).
  public let negative: Bool
  public let words: String
  public let maxWords: String
  /// The text for the language model, placeholders resolved: the answer rule and the notes.
  public let body: String
  /// The part of `body` after the «Model notes:» heading (all of it when there is none).
  public let notes: String
  /// There is a `custom/family-<id>.md` with something in it.
  public let isCustomized: Bool
}

/// The prompts that guide the language model for Enhance/Generate Prompt: Rules per task and Family per image-model
/// family, files in `Data/DTHub/` (the copies built into the app when a file is missing or not valid), and the user's
/// own in `custom/`. Read at every call, joined only here (spec «Prompt modulari»).
public struct PromptLibrary: Sendable {
  public let folderURL: URL

  public init(folder: URL) {
    folderURL = folder
  }

  /// ~/Library/Application Support/DT Hub/Data/DTHub.
  public static var live: PromptLibrary {
    PromptLibrary(
      folder: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DT Hub", isDirectory: true).appendingPathComponent("Data", isDirectory: true)
        .appendingPathComponent("DTHub", isDirectory: true))
  }

  public static let priorityLine = "In case of conflict, the instructions below take precedence over those above."

  // MARK: Reading

  private func read(_ path: String) -> String? {
    try? String(contentsOf: folderURL.appendingPathComponent(path), encoding: .utf8)
  }

  /// The file at `path` when it is valid and not older than the built-in copy; the built-in copy otherwise (with the
  /// reason in `problem`). `needsLabel`: a Family file without a label is not valid.
  private func load(_ path: String, embedded: String, needsLabel: Bool = false) -> (file: PromptFile, problem: String?) {
    let builtIn = PromptFile.parse(embedded)
    guard let text = read(path) else { return (builtIn, nil) }
    let file = PromptFile.parse(text)
    if !file.isValid || (needsLabel && (file.header["label"] ?? "").isEmpty) {
      return (builtIn, "\(path): the header is not valid; the built-in copy is used.")
    }
    if file.version < builtIn.version {
      return (builtIn, "\(path): version \(file.version) is older than the built-in \(builtIn.version); the built-in copy is used.")
    }
    return (file, nil)
  }

  private func values(of file: PromptFile) -> [String: String] {
    var result: [String: String] = [:]
    for key in ["label", "words", "maxWords"] { if let value = file.header[key] { result[key] = value } }
    return result
  }

  private func familyEntry(_ id: String) -> (prompt: FamilyPrompt, problems: [String])? {
    guard let embedded = EmbeddedPrompts.families[id] else { return nil }
    let (file, problem) = load("family/\(id).md", embedded: embedded, needsLabel: true)
    var problems = problem.map { [$0] } ?? []
    let values = values(of: file)
    let body = file.resolved(values).trimmingCharacters(in: .whitespacesAndNewlines)
    for key in ["words", "maxWords"] where values[key] == nil && file.body.contains("{\(key)}") {
      problems.append("family/\(id).md: {\(key)} is used but the header has no \(key).")
    }
    let notes = body.range(of: "Model notes:\n").map { String(body[$0.upperBound...]) } ?? body
    let prompt = FamilyPrompt(
      id: id, label: file.header["label"] ?? id, negative: file.header["negative"] == "true",
      words: file.header["words"] ?? "", maxWords: file.header["maxWords"] ?? "", body: body, notes: notes,
      isCustomized: custom("family-\(id).md") != nil)
    return (prompt, problems)
  }

  public func family(_ id: String?) -> FamilyPrompt? {
    id.flatMap { familyEntry($0)?.prompt }
  }

  /// The built-in families, with what the files say, sorted by label.
  public func families() -> [FamilyPrompt] {
    EmbeddedPrompts.families.keys.compactMap { familyEntry($0)?.prompt }
      .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
  }

  /// What is wrong with the files now (a header that does not read, an older version, a placeholder with no value).
  public func problems() -> [String] {
    var all: [String] = []
    for id in EmbeddedPrompts.families.keys.sorted() { all += familyEntry(id)?.problems ?? [] }
    for task in PromptTask.allCases {
      if let problem = load("rules/\(task.rawValue).md", embedded: EmbeddedPrompts.rules[task.rawValue] ?? "").problem {
        all.append(problem)
      }
    }
    return all
  }

  // MARK: The user's layer

  /// `custom/<name>`: nil when absent or with nothing in it.
  private func custom(_ name: String) -> (body: String, replaces: Bool)? {
    guard let text = read("custom/\(name)") else { return nil }
    let file = PromptFile.parse(text)
    let body = file.body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty else { return nil }
    return (body, file.header["mode"] == "replace")
  }

  /// For a language model with a system prompt of its own: what the user adds for the task, if anything.
  public func ownSystemAddition(task: PromptTask) -> String? {
    custom("\(task.rawValue).md").map { Self.priorityLine + "\n\n" + $0.body }
  }

  // MARK: Assembly

  /// Rules, Family, then the user's: the system prompt for a task and a family (the generic one without a known family).
  public func system(task: PromptTask, family id: String?) -> String {
    let known = id.flatMap { familyEntry($0)?.prompt }
    var rules: String
    var familyText: String
    if let known {
      let file = load("rules/\(task.rawValue).md", embedded: EmbeddedPrompts.rules[task.rawValue] ?? "").file
      rules = file.resolved(["label": known.label]).trimmingCharacters(in: .whitespacesAndNewlines)
      familyText = known.body
    } else {
      rules = EmbeddedPrompts.genericIntro
      familyText = PromptFile.parse(EmbeddedPrompts.genericFamily).body.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var appended: [String] = []
    if let mine = custom("\(task.rawValue).md") {
      if mine.replaces { rules = mine.body.replacingOccurrences(of: "{label}", with: known?.label ?? "") } else { appended.append(mine.body) }
    }
    if let id, let mine = custom("family-\(id).md") {
      if mine.replaces { familyText = mine.body.replacingOccurrences(of: "{label}", with: known?.label ?? "") } else { appended.append(mine.body) }
    }
    return ([rules, familyText] + appended.map { Self.priorityLine + "\n\n" + $0 }).joined(separator: "\n\n")
  }
}

// MARK: Installation

extension PromptLibrary {
  /// `custom/families.txt`: the names and ids of the families, to name the user's own files.
  public var familiesListURL: URL { folderURL.appendingPathComponent("custom/families.txt") }

  /// At launch: writes the base files that are missing, not readable, or older than the built-in copy (the old one
  /// is kept as `<name>.md.bak`), makes `custom/` and rewrites `families.txt`. A folder that cannot be written is
  /// no error: the built-in copies are used.
  public func install() {
    let manager = FileManager.default
    func place(_ path: String, embedded: String, needsLabel: Bool) {
      let url = folderURL.appendingPathComponent(path)
      try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      if let text = try? String(contentsOf: url, encoding: .utf8) {
        let file = PromptFile.parse(text)
        let usable = file.isValid && (!needsLabel || !(file.header["label"] ?? "").isEmpty)
        if usable && file.version >= PromptFile.parse(embedded).version { return }
        let backup = url.appendingPathExtension("bak")
        try? manager.removeItem(at: backup)
        try? manager.copyItem(at: url, to: backup)
      }
      try? embedded.write(to: url, atomically: true, encoding: .utf8)
    }
    for (id, text) in EmbeddedPrompts.families { place("family/\(id).md", embedded: text, needsLabel: true) }
    for (name, text) in EmbeddedPrompts.rules { place("rules/\(name).md", embedded: text, needsLabel: false) }
    try? manager.createDirectory(at: folderURL.appendingPathComponent("custom"), withIntermediateDirectories: true)
    let lines = families().map { "\($0.label) = \($0.id) (\($0.negative ? "negative prompt" : "no negative prompt"))" }
    let header = """
      Your own prompts go in this folder (custom/). They are added after the app's, and win if they disagree.
        enhance.md / describe.md      for Enhance Prompt / Generate Prompt, for every family
        family-<id>.md                for one family; <id> is the id in the list below
      A file may start with a header:  ---  then  mode: replace  then  ---   (replace the app's text instead of adding).
      The app's own files are in ../family and ../rules; changing those is not recommended.
      This list is rewritten at every launch.

      """
    try? (header + "\n" + lines.joined(separator: "\n") + "\n").write(to: familiesListURL, atomically: true, encoding: .utf8)
  }
}
