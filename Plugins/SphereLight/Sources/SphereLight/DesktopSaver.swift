import Foundation

/// Saves a copy of the sphere as "Sphere Light NNN.png", with the first free number: an earlier one is never overwritten.
enum DesktopSaver {
  static let prefix = "Sphere Light "

  static var desktopFolder: URL {
    FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
  }

  /// "Sphere Light 004.png" when the folder has 001 and 003: one more than the highest number.
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
