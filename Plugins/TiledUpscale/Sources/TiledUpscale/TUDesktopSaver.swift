import Foundation

/// Saves the enlarged picture on the Desktop as "Tiled Upscale NNN.png", with the first free number: an earlier file is
/// never overwritten.
enum TUDesktopSaver {
  static let prefix = "Tiled Upscale "

  static var desktopFolder: URL {
    FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
  }

  /// One more than the highest number of the prefix in the folder.
  static func nextURL(in folder: URL) -> URL {
    var highest = 0
    let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    for item in items {
      let name = item.deletingPathExtension().lastPathComponent
      guard name.hasPrefix(prefix), let number = Int(name.dropFirst(prefix.count)) else { continue }
      highest = max(highest, number)
    }
    return folder.appendingPathComponent(String(format: "%@%03d.png", prefix, highest + 1))
  }

  /// Writes `png` and returns where. Throws when the folder is not there or not writable.
  static func save(_ png: Data, in folder: URL = desktopFolder) throws -> URL {
    let url = nextURL(in: folder)
    try png.write(to: url, options: .withoutOverwriting)
    return url
  }
}
