import Foundation

/// A folder with one `<name>.json` per item (presets, the user's pipelines). Names follow the file system's rules:
/// no "/" or ":", and capitals and accents do not tell two names apart.
@MainActor
struct NamedJSONFolder {
  let folder: URL
  /// Moves a file; the tests give one that fails.
  let move: (URL, URL) throws -> Void

  init(folder: URL, move: @escaping (URL, URL) throws -> Void) {
    self.folder = folder
    self.move = move
  }

  /// The names of the files, sorted (a file added, changed or removed by hand shows up).
  func names() -> [String] {
    let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    return files
      .filter { $0.pathExtension.lowercased() == "json" && !$0.lastPathComponent.hasPrefix(".") }
      .map { $0.deletingPathExtension().lastPathComponent }
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }

  /// A name the file system takes: not empty once trimmed, no "/" or ":", not starting with a dot, at most 120
  /// characters and 240 bytes (the file system's limit is 255 bytes, ".json" included).
  nonisolated static func isValidName(_ raw: String) -> Bool {
    let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return !name.isEmpty && name.count <= 120 && name.utf8.count <= 240 && !name.hasPrefix(".") && !name.contains("/")
      && !name.contains(":")
  }

  /// The name as it is written in the folder, if an item has this name. The exact name wins; then the name
  /// without the spaces at its ends; then a name that differs only by capitals or accents. (The file system
  /// keeps apart two files that differ only by an accent, if someone put them there by hand.)
  func existingName(for name: String) -> String? {
    let names = names()
    let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return names.first { $0 == name } ?? names.first { $0 == wanted } ?? names.first { Self.same($0, wanted) }
  }

  /// The contents of the file with this exact name.
  func data(named actual: String) -> Data? { try? Data(contentsOf: url(actual)) }

  func write(_ data: Data, as name: String) throws(PresetError) {
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try data.write(to: url(name), options: .atomic)
    } catch {
      throw .cannotWrite(error.localizedDescription)
    }
  }

  /// Renames the file. Changing only the capitals of a name is allowed.
  func rename(_ old: String, to newName: String) throws(PresetError) {
    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard Self.isValidName(name) else { throw .invalidName }
    guard let actual = existingName(for: old) else { throw .notFound(old) }
    if let other = existingName(for: name), other != actual { throw .nameTaken }
    guard actual != name else { return }
    // Two steps: on a file system that ignores capitals a one-step move to a name that differs only by them can fail.
    let temporary = folder.appendingPathComponent(".renaming-\(UUID().uuidString).json")
    do {
      try move(url(actual), temporary)
    } catch {
      throw .cannotWrite(error.localizedDescription)
    }
    do {
      try move(temporary, url(name))
    } catch {
      // The file goes back where it was: one left under the temporary name would be hidden from the list.
      try? move(temporary, url(actual))
      throw .cannotWrite(error.localizedDescription)
    }
  }

  func remove(named name: String) {
    guard let actual = existingName(for: name) else { return }
    try? FileManager.default.removeItem(at: url(actual))
  }

  nonisolated static func same(_ a: String, _ b: String) -> Bool {
    a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
  }

  private func url(_ name: String) -> URL { folder.appendingPathComponent(name + ".json") }
}
