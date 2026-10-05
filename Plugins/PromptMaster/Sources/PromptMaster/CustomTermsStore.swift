import Foundation

/// The user's own terms, in `custom-terms.json` of the plug-in's folder (spec §4). Apart from the database, so
/// replacing the database does not delete them.
struct CustomTermsStore {
  enum Failure: Error, Equatable {
    /// The text is empty.
    case empty
    /// The file exists and cannot be read: it is left alone rather than overwritten.
    case unreadableFile
    case cannotWrite
  }

  static let fileName = "custom-terms.json"
  static let maxLength = 200
  static let schema = 1

  var folder: URL = DataSource.defaultFolder.appendingPathComponent(PMData.pluginFolderName, isDirectory: true)

  private struct File: Codable {
    var schema: Int
    var terms: [CustomTerm]
  }

  private var fileURL: URL { folder.appendingPathComponent(Self.fileName) }

  /// The terms; none when the file is missing or unreadable.
  func load() -> [CustomTerm] { (try? read()) ?? [] }

  private func read() throws -> [CustomTerm] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
    guard let data = try? Data(contentsOf: fileURL), let file = try? JSONDecoder().decode(File.self, from: data),
      file.schema == Self.schema
    else { throw Failure.unreadableFile }
    return file.terms
  }

  /// Adds a term to a category. The same text (ignoring case) in the same category is not added twice: the existing
  /// term comes back.
  @discardableResult
  func add(text: String, to categoryID: String) throws -> CustomTerm {
    let clean = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxLength))
    guard !clean.isEmpty else { throw Failure.empty }
    var terms = try read()
    if let same = terms.first(where: { $0.categoryID == categoryID && $0.text.caseInsensitiveCompare(clean) == .orderedSame }) {
      return same
    }
    let term = CustomTerm(id: "custom-\(UUID().uuidString)", categoryID: categoryID, text: clean)
    terms.append(term)
    try write(terms)
    return term
  }

  func remove(id: String) throws {
    var terms = try read()
    terms.removeAll { $0.id == id }
    try write(terms)
  }

  private func write(_ terms: [CustomTerm]) throws {
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(File(schema: Self.schema, terms: terms)).write(to: fileURL, options: .atomic)
    } catch {
      throw Failure.cannotWrite
    }
  }
}
