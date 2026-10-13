import CryptoKit
import Foundation

/// What the plug-in keeps for one LoRA (spec §5). Every field is optional in the file; one that is missing or of the
/// wrong type takes its default.
struct LAEntry: Codable, Equatable {
  /// The page of the LoRA (Civitai or Hugging Face).
  var link: String?
  var notes: String
  /// The name of the picture in `thumbs/`.
  var thumbnail: String?
  /// "Find pages" has been on this LoRA already, found or not: it does not search it again.
  var searched: Bool
  /// The link comes from the search, not from the user.
  var foundBySearch: Bool
  /// The notes are still the raw text of the page, waiting for the summary.
  var rawNotes: Bool
  /// The user chose the thumbnail (a file, or the Control tab's picture): an import does not replace it.
  var manualThumbnail: Bool

  init(
    link: String? = nil, notes: String = "", thumbnail: String? = nil, searched: Bool = false, foundBySearch: Bool = false,
    rawNotes: Bool = false, manualThumbnail: Bool = false
  ) {
    self.link = link
    self.notes = notes
    self.thumbnail = thumbnail
    self.searched = searched
    self.foundBySearch = foundBySearch
    self.rawNotes = rawNotes
    self.manualThumbnail = manualThumbnail
  }

  var isEmpty: Bool { self == LAEntry() }

  private enum CodingKeys: String, CodingKey {
    case link, notes, thumbnail, searched, foundBySearch, rawNotes, manualThumbnail
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    func text(_ key: CodingKeys) -> String? {
      ((try? container.decodeIfPresent(String.self, forKey: key)) ?? nil).flatMap { $0.isEmpty ? nil : $0 }
    }
    func flag(_ key: CodingKeys) -> Bool { ((try? container.decodeIfPresent(Bool.self, forKey: key)) ?? nil) ?? false }
    self.init(
      link: text(.link), notes: text(.notes) ?? "", thumbnail: text(.thumbnail), searched: flag(.searched),
      foundBySearch: flag(.foundBySearch), rawNotes: flag(.rawNotes), manualThumbnail: flag(.manualThumbnail))
  }

  /// Only what is not the default is written.
  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(link, forKey: .link)
    if !notes.isEmpty { try container.encode(notes, forKey: .notes) }
    try container.encodeIfPresent(thumbnail, forKey: .thumbnail)
    if searched { try container.encode(true, forKey: .searched) }
    if foundBySearch { try container.encode(true, forKey: .foundBySearch) }
    if rawNotes { try container.encode(true, forKey: .rawNotes) }
    if manualThumbnail { try container.encode(true, forKey: .manualThumbnail) }
  }
}

/// The notes and thumbnails of the LoRAs, on disk (spec §5): `loras.json`, `thumbs/` and `pages/` in one folder. They
/// are global, not per project: they are about the LoRA. Entries are keyed by the LoRA's file name, and those of
/// LoRAs the server no longer has are kept.
@MainActor
final class LAStore {
  static let schema = 1
  private(set) var entries: [String: LAEntry] = [:]
  /// `loras.json` is there and cannot be read: it is left alone until the user changes something.
  private(set) var isUnreadable = false
  private let folder: URL

  init(folder: URL) {
    self.folder = folder
    load()
  }

  /// ~/Library/Application Support/DT Hub/Data/LoRAAdvisor.
  static var defaultFolder: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true)
      .appendingPathComponent("Data", isDirectory: true)
      .appendingPathComponent("LoRAAdvisor", isDirectory: true)
  }

  func entry(for file: String) -> LAEntry { entries[file] ?? LAEntry() }

  /// Changes the entry of a LoRA and writes the file at once. An entry with nothing in it leaves the file.
  func update(_ file: String, _ change: (inout LAEntry) -> Void) {
    var entry = entry(for: file)
    change(&entry)
    guard entry != entries[file] ?? LAEntry() || isUnreadable else { return }
    entries[file] = entry.isEmpty ? nil : entry
    save()
  }

  /// The user wrote the notes: they are theirs, and no automatic pass touches them any more.
  func setNotesByUser(_ text: String, for file: String) {
    setPageText(nil, for: file)
    update(file) {
      $0.notes = text
      $0.rawNotes = false
    }
  }

  /// A new thumbnail (JPEG data), or none. The picture it replaces is deleted.
  func setThumbnail(_ jpeg: Data?, manual: Bool, for file: String) {
    let old = entry(for: file).thumbnail
    var name: String?
    if let jpeg {
      let fresh = UUID().uuidString + ".jpg"
      do {
        try FileManager.default.createDirectory(at: thumbs, withIntermediateDirectories: true)
        try jpeg.write(to: thumbs.appendingPathComponent(fresh), options: .atomic)
        name = fresh
      } catch {
        return
      }
    }
    if let old { try? FileManager.default.removeItem(at: thumbs.appendingPathComponent(old)) }
    update(file) {
      $0.thumbnail = name
      $0.manualThumbnail = name != nil && manual
    }
  }

  func thumbnailURL(for file: String) -> URL? {
    entry(for: file).thumbnail.map { thumbs.appendingPathComponent($0) }
  }

  /// The cleaned text of the LoRA's page, kept while its notes are raw so the summary needs no download.
  func setPageText(_ text: String?, for file: String) {
    let url = pageURL(for: file)
    guard let text else {
      try? FileManager.default.removeItem(at: url)
      return
    }
    try? FileManager.default.createDirectory(at: pages, withIntermediateDirectories: true)
    try? Data(text.utf8).write(to: url, options: .atomic)
  }

  func pageText(for file: String) -> String? {
    (try? Data(contentsOf: pageURL(for: file))).flatMap { String(data: $0, encoding: .utf8) }
  }

  // MARK: Private

  private var fileURL: URL { folder.appendingPathComponent("loras.json") }
  private var thumbs: URL { folder.appendingPathComponent("thumbs", isDirectory: true) }
  private var pages: URL { folder.appendingPathComponent("pages", isDirectory: true) }

  /// A LoRA's file name can hold anything; its page is filed under the SHA-256 of the name.
  private func pageURL(for file: String) -> URL {
    let digest = SHA256.hash(data: Data(file.utf8)).map { String(format: "%02x", $0) }.joined()
    return pages.appendingPathComponent(digest + ".txt")
  }

  private struct File: Codable {
    var schema: Int
    var loras: [String: Lenient]
  }

  /// An entry that is not an object is left out without costing the others.
  private struct Lenient: Codable {
    var entry: LAEntry?
    init(_ entry: LAEntry) { self.entry = entry }
    init(from decoder: any Decoder) throws { entry = try? LAEntry(from: decoder) }
    func encode(to encoder: any Encoder) throws { try entry?.encode(to: encoder) }
  }

  private func load() {
    guard let data = try? Data(contentsOf: fileURL) else { return }
    guard let file = try? JSONDecoder().decode(File.self, from: data), file.schema == Self.schema else {
      isUnreadable = true
      return
    }
    entries = file.loras.compactMapValues { $0.entry.flatMap { $0.isEmpty ? nil : $0 } }
  }

  private func save() {
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      if isUnreadable {
        // What was there is not thrown away: the user may want to mend it by hand.
        let backup = folder.appendingPathComponent("loras.json.bak")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: fileURL, to: backup)
        isUnreadable = false
      }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(File(schema: Self.schema, loras: entries.mapValues(Lenient.init))).write(to: fileURL, options: .atomic)
    } catch {
      // A failure only loses the change at the next launch.
    }
  }
}
