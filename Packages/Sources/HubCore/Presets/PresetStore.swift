import Foundation
import HubKit
import Observation

/// The saved presets (spec §6), kept in a JSON file in the app's support folder (spec §11).
/// Names are unique, compared without regard to case.
@MainActor
@Observable
public final class PresetStore {
  /// By name.
  public private(set) var presets: [Preset]
  @ObservationIgnored private let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
    let data = try? Data(contentsOf: fileURL)
    presets = (data.flatMap { try? JSONDecoder().decode([LossyPreset].self, from: $0) } ?? [])
      .compactMap(\.preset)
    presets = Self.sorted(presets)
  }

  /// ~/Library/Application Support/DT Hub/presets.json.
  public static var defaultFileURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true)
      .appendingPathComponent("presets.json")
  }

  public func preset(named name: String) -> Preset? {
    presets.first { Self.same($0.name, name) }
  }

  /// Saves under `preset.name`, replacing the preset of the same name. An empty name is refused.
  @discardableResult
  public func save(_ preset: Preset) -> Bool {
    var preset = preset.withoutSize()
    preset.name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !preset.name.isEmpty else { return false }
    if let index = presets.firstIndex(where: { Self.same($0.name, preset.name) }) {
      preset.id = presets[index].id
      presets[index] = preset
    } else {
      presets.append(preset)
    }
    commit()
    return true
  }

  public func delete(_ id: Preset.ID) {
    presets.removeAll { $0.id == id }
    commit()
  }

  /// False when the new name is empty or taken by another preset.
  @discardableResult
  public func rename(_ id: Preset.ID, to newName: String) -> Bool {
    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, let index = presets.firstIndex(where: { $0.id == id }),
      !presets.contains(where: { $0.id != id && Self.same($0.name, name) })
    else { return false }
    presets[index].name = name
    commit()
    return true
  }

  /// Adds imported presets, each under a free name ("Name", "Name (2)", …): nothing the
  /// user saved is replaced.
  public func add(imported: [Preset]) {
    for var preset in imported {
      let base = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
      var name = base
      var number = 2
      while presets.contains(where: { Self.same($0.name, name) }) {
        name = "\(base) (\(number))"
        number += 1
      }
      preset.name = name
      preset.id = UUID()
      presets.append(preset)
    }
    commit()
  }

  private func commit() {
    presets = Self.sorted(presets)
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(presets).write(to: fileURL, options: .atomic)
    } catch {
      // A write failure only loses the memory of the change.
    }
  }

  private static func same(_ a: String, _ b: String) -> Bool {
    a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
  }

  private static func sorted(_ presets: [Preset]) -> [Preset] {
    presets.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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

/// One element of the file, decoded on its own: a damaged preset does not take the others.
private struct LossyPreset: Decodable {
  let preset: Preset?

  init(from decoder: any Decoder) throws {
    preset = try? Preset(from: decoder)
  }
}
