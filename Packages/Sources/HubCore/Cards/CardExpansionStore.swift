import Foundation
import Observation

/// Which cards of the Generation tab are open, remembered across launches in a JSON file in
/// the app's support folder (spec §7, §11). Cards never touched use their default.
@MainActor
@Observable
public final class CardExpansionStore {
  private var expanded: [String: Bool]
  @ObservationIgnored private let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
    let data = try? Data(contentsOf: fileURL)
    expanded = data.flatMap { try? JSONDecoder().decode([String: Bool].self, from: $0) } ?? [:]
  }

  /// ~/Library/Application Support/DT Hub/cards.json.
  public static var defaultFileURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true)
      .appendingPathComponent("cards.json")
  }

  public func isExpanded(_ card: String, default defaultValue: Bool = true) -> Bool {
    expanded[card] ?? defaultValue
  }

  /// Records the state and writes the file; a write failure only loses the memory of it.
  public func setExpanded(_ value: Bool, for card: String) {
    expanded[card] = value
    try? FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? JSONEncoder().encode(expanded).write(to: fileURL, options: .atomic)
  }
}
