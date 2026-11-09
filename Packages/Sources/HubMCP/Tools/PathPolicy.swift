import Foundation

/// Which picture files an agent may point the app at (spec §6): only inside the allowed folders, only pictures.
public struct PathPolicy: Sendable {
  private let roots: [[String]]
  static let pictureExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "heic"]

  public init(roots: [URL]) {
    self.roots = roots.map { Self.components(of: $0) }
  }

  /// The canonical file URL when `path` is an absolute path to an existing picture inside a root; nil otherwise.
  public func resolve(_ path: String) -> URL? {
    guard path.hasPrefix("/") else { return nil }
    let url = URL(fileURLWithPath: path)
    guard Self.pictureExtensions.contains(url.pathExtension.lowercased()) else { return nil }
    let canonical = url.resolvingSymlinksInPath().standardizedFileURL
    guard FileManager.default.fileExists(atPath: canonical.path) else { return nil }
    let parts = Self.components(of: canonical)
    guard roots.contains(where: { root in !root.isEmpty && parts.count > root.count && Array(parts.prefix(root.count)) == root })
    else { return nil }
    return canonical
  }

  private static func components(of url: URL) -> [String] {
    url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
  }
}
