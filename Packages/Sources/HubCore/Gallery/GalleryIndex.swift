import Foundation

/// One picture of the Explore gallery: where it is, when it was made, which project (or extra folder) it belongs to,
/// and the text the search looks in (folded: lower case, no accents).
public struct GalleryEntry: Codable, Equatable, Identifiable, Sendable {
  public let path: String
  public let date: Date
  public let project: String
  public let searchText: String
  /// Size and modification date of the file when it was read: what tells a changed file from an unchanged one.
  public let fileSize: Int
  public let modified: Date

  public var id: String { path }
  public var url: URL { URL(fileURLWithPath: path) }

  public init(path: String, date: Date, project: String, searchText: String, fileSize: Int = 0, modified: Date = .distantPast) {
    self.path = path
    self.date = date
    self.project = project
    self.searchText = searchText
    self.fileSize = fileSize
    self.modified = modified
  }

  /// Lower case and without accents: what the search compares.
  public static func searchKey(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
  }
}

/// The pictures of every project of the output folder and of the extra folders, kept in a file so that the next launch
/// shows them at once and only reads the pictures that are new or changed.
public struct GalleryIndex: Sendable {
  public let cacheURL: URL

  public init(cacheURL: URL) {
    self.cacheURL = cacheURL
  }

  public static var defaultCacheURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true)
      .appendingPathComponent("gallery-index.json")
  }

  /// What the last `refresh` found (nothing when the file is missing or broken).
  public func cached() -> [GalleryEntry] {
    guard let data = try? Data(contentsOf: cacheURL) else { return [] }
    return (try? JSONDecoder().decode([GalleryEntry].self, from: data)) ?? []
  }

  /// The metadata text of a picture: its PNG description and its comment.
  public static let fileReader: @Sendable (URL) -> String = { url in
    [PNGImageStore.description(in: url), PNGImageStore.comment(in: url)].compactMap { $0 }.joined(separator: " ")
  }

  /// Scans the projects and the extra folders, rereads only the pictures that are new or changed, saves the result and
  /// returns it, newest first. Heavy: call it off the main actor.
  public func refresh(
    outputFolder: URL, extraFolders: [URL], reader: @Sendable (URL) -> String = GalleryIndex.fileReader
  ) -> [GalleryEntry] {
    let known = Dictionary(cached().map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
    var seen: Set<String> = []
    var entries: [GalleryEntry] = []

    func add(_ url: URL, date: Date, project: String) {
      let path = url.standardizedFileURL.path
      guard seen.insert(path).inserted else { return }
      let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
      let size = values?.fileSize ?? 0
      let modified = values?.contentModificationDate ?? .distantPast
      if let old = known[path], old.fileSize == size, old.modified == modified, old.project == project {
        entries.append(old)
        return
      }
      let text = Self.text(reader(url), project: project, name: url.lastPathComponent)
      entries.append(
        GalleryEntry(path: path, date: date, project: project, searchText: text, fileSize: size, modified: modified))
    }

    for project in ProjectCatalog(outputFolder: outputFolder).projects() {
      for image in ProjectImages.allImages(in: project.folder) { add(image.url, date: image.date, project: project.name) }
    }
    for folder in extraFolders {
      let name = folder.lastPathComponent
      guard
        let walker = FileManager.default.enumerator(
          at: folder, includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
          options: [.skipsHiddenFiles, .skipsPackageDescendants])
      else { continue }
      for case let url as URL in walker where url.pathExtension.lowercased() == "png" {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        add(url, date: values?.creationDate ?? values?.contentModificationDate ?? .distantPast, project: name)
      }
    }

    entries.sort { $0.date > $1.date }
    save(entries)
    return entries
  }

  private static func text(_ metadata: String, project: String, name: String) -> String {
    GalleryEntry.searchKey([metadata, project, name].filter { !$0.isEmpty }.joined(separator: " "))
  }

  private func save(_ entries: [GalleryEntry]) {
    do {
      try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(entries).write(to: cacheURL, options: .atomic)
    } catch {
    }
  }
}
