import Foundation
import HubCore

/// What the Explore tab does with pictures that may not be in the session's strip.
@MainActor
enum GalleryActions {
  /// The picture of a gallery file with its job (for the sidebar and "Resume parameters"); nil when the file holds none.
  static func image(for entry: GalleryEntry) async -> GeneratedImage? {
    let (url, date) = (entry.url, entry.date)
    return await Task.detached { GeneratedImage.fromFile(url, date: date, maxPixel: 2048) }.value
  }

  /// Moves the pictures to the Trash (the strip of the session drops the ones it holds) and takes the ones that are
  /// gone out of the gallery. Returns what could not be trashed.
  static func trash(_ entries: [GalleryEntry], controller: GenerationController) -> [String] {
    let paths = Set(entries.map(\.path))
    let inStrip = controller.session.results.filter { result in
      result.fileURL.map { paths.contains($0.standardizedFileURL.path) } ?? false
    }
    var failures = controller.session.remove(Set(inStrip.map(\.id)))
    let held = Set(inStrip.compactMap { $0.fileURL?.standardizedFileURL.path })
    let store = PNGImageStore(folder: controller.outputFolder)
    for entry in entries where !held.contains(entry.path) {
      do {
        try store.trash(entry.url)
      } catch {
        failures.append("\(entry.url.lastPathComponent): \(error)")
      }
    }
    let gone = Set(entries.filter { !FileManager.default.fileExists(atPath: $0.path) }.map(\.path))
    controller.gallery.removeEntries(gone)
    return failures
  }
}
