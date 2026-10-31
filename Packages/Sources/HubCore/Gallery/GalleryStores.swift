import Foundation

/// A small JSON file in `~/Library/Application Support/DT Hub/`: read as a default value when missing or broken,
/// written atomically; a failed write only loses the change at the next launch.
private enum GalleryFile {
  static func defaultURL(_ name: String) -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true)
      .appendingPathComponent(name)
  }

  static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }

  static func save<T: Encodable>(_ value: T, to url: URL) {
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(value).write(to: url, options: .atomic)
    } catch {
    }
  }
}

/// The folders added by hand to the Explore gallery (`gallery-folders.json`: an array of paths).
public struct GalleryFoldersStore: Sendable {
  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public static var defaultFileURL: URL { GalleryFile.defaultURL("gallery-folders.json") }

  public func load() -> [URL] {
    (GalleryFile.load([String].self, from: fileURL) ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) }
  }

  public func save(_ folders: [URL]) {
    GalleryFile.save(folders.map(\.path), to: fileURL)
  }
}

/// The pictures marked with the star (`favorites.json`: a set of file paths).
public struct FavoritesStore: Sendable {
  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public static var defaultFileURL: URL { GalleryFile.defaultURL("favorites.json") }

  public func load() -> Set<String> {
    Set(GalleryFile.load([String].self, from: fileURL) ?? [])
  }

  public func save(_ paths: Set<String>) {
    GalleryFile.save(paths.sorted(), to: fileURL)
  }
}
