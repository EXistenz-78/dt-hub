import Foundation
import Observation

/// The pipelines the user saved: a folder with one `<name>.json` per pipeline, like the presets (`PresetStore`).
/// Their names are apart from the presets': a pipeline and a preset can have the same name.
@MainActor
@Observable
public final class UserPipelineStore {
  /// The names of the pipelines, sorted; read from the folder by `refresh()`.
  public private(set) var names: [String] = []
  @ObservationIgnored private let files: NamedJSONFolder

  public init(folder: URL, move: @escaping (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }) {
    files = NamedJSONFolder(folder: folder, move: move)
    refresh()
  }

  /// ~/Library/Application Support/DT Hub/Pipelines.
  public static var defaultFolder: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true)
      .appendingPathComponent("Pipelines", isDirectory: true)
  }

  /// Reads the folder again (a file added, changed or removed by hand shows up).
  public func refresh() {
    let list = files.names()
    if list != names { names = list }
  }

  /// The name as it is written in the folder, if a pipeline has this name (capitals and accents do not count).
  public func existingName(for name: String) -> String? {
    refresh()
    return files.existingName(for: name)
  }

  public func contains(_ name: String) -> Bool { existingName(for: name) != nil }

  /// Reads the file of a pipeline, now.
  public func load(named name: String) throws(PresetError) -> UserPipeline {
    guard let actual = existingName(for: name) else { throw .notFound(name) }
    guard let data = files.data(named: actual), let pipeline = UserPipeline(data: data) else { throw .unreadable(actual) }
    return pipeline
  }

  /// Saves under `name`, replacing the file of the same name.
  public func save(_ pipeline: UserPipeline, named raw: String) throws(PresetError) {
    let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard NamedJSONFolder.isValidName(name) else { throw .invalidName }
    defer { refresh() }
    try files.write(pipeline.data(), as: existingName(for: name) ?? name)
  }

  public func delete(named name: String) {
    files.remove(named: name)
    refresh()
  }

  /// Renames the file. Changing only the capitals of a name is allowed.
  public func rename(_ old: String, to newName: String) throws(PresetError) {
    defer { refresh() }
    try files.rename(old, to: newName)
  }

  /// A preset was renamed: the pipelines that name it follow. The others, and the files that cannot be read, are
  /// left as they are.
  public func renamePreset(_ old: String, to newName: String) {
    refresh()
    for name in names {
      guard var pipeline = try? load(named: name) else { continue }
      var changed = false
      for index in pipeline.steps.indices {
        if let preset = pipeline.steps[index].preset, NamedJSONFolder.same(preset, old), preset != newName {
          pipeline.steps[index].preset = newName
          changed = true
        }
      }
      if changed { try? files.write(pipeline.data(), as: name) }
    }
  }
}
