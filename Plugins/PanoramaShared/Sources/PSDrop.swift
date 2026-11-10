import Foundation
import UniformTypeIdentifiers

/// What the canvas takes: files (Finder, the Results strip of DT Hub) and picture data (dragged from a browser). A bare web address is not followed.
enum PSDrop {
  static let types: [UTType] = [.fileURL, .image]

  /// Gathers the files of the dropped items, in the order dropped (picture data is written into `tempFolder` first), then calls `done`.
  @MainActor
  static func collect(_ providers: [NSItemProvider], tempFolder: URL, done: @escaping @MainActor ([URL]) -> Void) {
    let gatherer = Gatherer(count: providers.count, done: done)
    for (index, provider) in providers.enumerated() {
      if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
          Task { @MainActor in gatherer.finish(index, url.flatMap { $0.isFileURL ? $0 : nil }) }
        }
      } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
          Task { @MainActor in gatherer.finish(index, data.flatMap { write($0, in: tempFolder) }) }
        }
      } else {
        Task { @MainActor in gatherer.finish(index, nil) }
      }
    }
  }

  @MainActor
  private final class Gatherer {
    private var urls: [URL?]
    private var remaining: Int
    private let done: @MainActor ([URL]) -> Void

    init(count: Int, done: @escaping @MainActor ([URL]) -> Void) {
      urls = Array(repeating: nil, count: count)
      remaining = count
      self.done = done
    }

    func finish(_ index: Int, _ url: URL?) {
      urls[index] = url
      remaining -= 1
      if remaining == 0 { done(urls.compactMap { $0 }) }
    }
  }

  private static func write(_ data: Data, in folder: URL) -> URL? {
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("drop-\(UUID().uuidString).img")
    return (try? data.write(to: url)) == nil ? nil : url
  }
}
