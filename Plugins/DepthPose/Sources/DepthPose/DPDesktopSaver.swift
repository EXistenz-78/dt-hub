import Foundation

/// Saves a copy of a map on the Desktop as "Depth NNN.png" or "Pose NNN.png", with the first free number for that name:
/// an earlier file is never overwritten.
enum DPDesktopSaver {
  static var desktopFolder: URL {
    FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
  }

  /// "Depth 004.png" when the folder has Depth 001 and 003: one more than the highest number of that prefix.
  static func nextURL(prefix: String, in folder: URL) -> URL {
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
  static func save(_ png: Data, prefix: String, in folder: URL = desktopFolder) throws -> URL {
    let url = nextURL(prefix: prefix, in: folder)
    try png.write(to: url, options: .withoutOverwriting)
    return url
  }
}
