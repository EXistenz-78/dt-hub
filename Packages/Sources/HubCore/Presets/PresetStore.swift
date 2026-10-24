import Foundation
import HubKit
import Observation

/// Why a preset could not be read or written.
public enum PresetError: Error, Equatable, Sendable {
  /// Empty, with a "/" or a ":", or starting with a dot: not a name the file system takes.
  case invalidName
  case nameTaken
  case notFound(String)
  /// The file is there and is not a preset.
  case unreadable(String)
  case cannotWrite(String)
}

/// The saved presets (spec §6, and `2026-10-04-preset-pipeline-design.md` §8): a folder with one `<name>.json`
/// per preset. The list is the names of the files; a file is read only when its preset is needed. Names follow
/// the file system's rules: no "/" or ":", and capitals and accents do not tell two names apart.
@MainActor
@Observable
public final class PresetStore {
  /// The names of the presets, sorted; read from the folder by `refresh()`.
  public private(set) var names: [String] = []
  /// The preset the user loaded last, as asked for; `activeName` is the name its file has now.
  @ObservationIgnored private var loaded: String?
  @ObservationIgnored private let files: NamedJSONFolder

  public init(folder: URL, move: @escaping (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }) {
    files = NamedJSONFolder(folder: folder, move: move)
    refresh()
  }

  /// ~/Library/Application Support/DT Hub/Presets.
  public static var defaultFolder: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true)
      .appendingPathComponent("Presets", isDirectory: true)
  }

  /// Reads the folder again (a file added, changed or removed by hand shows up).
  public func refresh() {
    let list = files.names()
    if list != names { names = list }
  }

  /// A name the file system takes: not empty once trimmed, no "/" or ":", not starting with a dot, at most 120
  /// characters and 240 bytes (the file system's limit is 255 bytes, ".json" included).
  public nonisolated static func isValidName(_ raw: String) -> Bool { NamedJSONFolder.isValidName(raw) }

  /// The name as it is written in the folder, if a preset has this name. The exact name wins; then the name
  /// without the spaces at its ends; then a name that differs only by capitals or accents.
  public func existingName(for name: String) -> String? {
    refresh()
    return files.existingName(for: name)
  }

  public func contains(_ name: String) -> Bool { existingName(for: name) != nil }

  /// Reads the file of a preset, now.
  public func load(named name: String) throws(PresetError) -> Preset {
    guard let actual = existingName(for: name) else { throw .notFound(name) }
    guard let data = files.data(named: actual), var preset = try? JSONDecoder().decode(Preset.self, from: data)
    else { throw .unreadable(actual) }
    preset.name = actual
    return preset
  }

  /// Remembers that this preset was put on the tab, so "update preset" knows which file to replace. Kept for the session only.
  public func markLoaded(_ name: String) { loaded = name }

  /// The preset on the tab, under the name of its file; nil when none was loaded or its file is gone (deleted, or renamed by hand).
  public var activeName: String? { loaded.flatMap { existingName(for: $0) } }

  /// The preset, or nil when there is none or its file cannot be read.
  public func preset(named name: String) -> Preset? { try? load(named: name) }

  /// Saves under `preset.name`, replacing the file of the same name. The size is not kept.
  public func save(_ preset: Preset) throws(PresetError) {
    let name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard Self.isValidName(name) else { throw .invalidName }
    try write(preset.withoutSize(), as: existingName(for: name) ?? name)
  }

  public func delete(named name: String) {
    files.remove(named: name)
    refresh()
  }

  /// Renames the file. Changing only the capitals of a name is allowed.
  public func rename(_ old: String, to newName: String) throws(PresetError) {
    defer { refresh() }
    let wasActive = activeName == old
    try files.rename(old, to: newName)
    if wasActive { loaded = newName.trimmingCharacters(in: .whitespacesAndNewlines) }
  }

  /// Adds imported presets, each under a free name ("Name", "Name (2)", …); a "/" or ":" in a name becomes "-".
  /// Nothing the user saved is replaced.
  public func add(imported: [Preset]) {
    for var preset in imported {
      let base = preset.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard Self.isValidName(base) else { continue }
      var name = base
      var number = 2
      while contains(name) {
        name = "\(base) (\(number))"
        number += 1
      }
      preset.name = name
      try? write(preset.withoutSize(), as: name)
    }
  }

  /// Adds the presets a plug-in brought. A name that is taken, by the user's own preset or by an earlier one of
  /// the plug-in, is never touched (the user may have changed it); a name the file system does not take is left
  /// out. Returns how many were added, were there already, and were refused.
  @discardableResult
  public func add(fromPlugin newPresets: [Preset]) -> (added: Int, existing: Int, rejected: Int) {
    var added = 0
    var existing = 0
    var rejected = 0
    for preset in newPresets {
      let name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard Self.isValidName(name) else {
        rejected += 1
        continue
      }
      if contains(name) {
        existing += 1
        continue
      }
      if (try? write(preset.withoutSize(), as: name)) != nil { added += 1 } else { rejected += 1 }
    }
    return (added, existing, rejected)
  }

  // MARK: Private

  private func write(_ preset: Preset, as name: String) throws(PresetError) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(preset) else { throw .cannotWrite(name) }
    try files.write(data, as: name)
    refresh()
  }
}

extension Preset {
  /// The preset with the size of a new `GenerationParameters`: a preset does not keep one.
  fileprivate func withoutSize() -> Preset {
    var copy = self
    copy.parameters.width = GenerationParameters.default.width
    copy.parameters.height = GenerationParameters.default.height
    return copy
  }
}
