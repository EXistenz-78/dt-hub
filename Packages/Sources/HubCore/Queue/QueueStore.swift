import Foundation
import HubKit
import Observation

/// The queue of generations of the open project (queue design §4): `queue.json` in the project's Queue folder, and one
/// folder per entry (`<Queue>/<id>`) with the copies of its pictures. Follows the open project like `ControlStore`.
@MainActor
@Observable
public final class QueueStore {
  public private(set) var entries: [QueueEntry] = []
  /// The Queue folder of the open project; nil while no project is open (the queue then lives in memory only).
  @ObservationIgnored private var folder: URL?

  public init(folder: URL?) {
    self.folder = folder
    load()
  }

  /// Follows another project (or none): its queue is read from its folder.
  public func switchTo(folder: URL?) {
    self.folder = folder
    load()
  }

  /// Where an entry keeps its pictures.
  public func folder(for id: UUID) -> URL {
    (folder ?? FileManager.default.temporaryDirectory.appendingPathComponent("DTHubQueue", isDirectory: true))
      .appendingPathComponent(id.uuidString, isDirectory: true)
  }

  public var firstPending: QueueEntry? { entries.first { $0.status == .pending } }

  public func add(_ entry: QueueEntry) {
    entries.append(entry)
    save()
  }

  public func remove(id: UUID) {
    entries.removeAll { $0.id == id }
    try? FileManager.default.removeItem(at: folder(for: id))
    save()
  }

  public func move(from source: IndexSet, to destination: Int) {
    let moving = source.sorted().map { entries[$0] }
    let before = source.filter { $0 < destination }.count
    for index in source.sorted().reversed() { entries.remove(at: index) }
    entries.insert(contentsOf: moving, at: destination - before)
    save()
  }

  /// Takes every entry away, with its pictures.
  public func clear() {
    for entry in entries { try? FileManager.default.removeItem(at: folder(for: entry.id)) }
    entries = []
    save()
  }

  public func setStatus(_ status: QueueStatus, for id: UUID) {
    guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].status != status else { return }
    entries[index].status = status
    save()
  }

  /// Copies the pictures the steps name (Moodboard, start image, mask) into the entry's folder and points the steps at
  /// the copies. A picture that is gone throws; nothing is kept then.
  public func copyingImages(of steps: [PipelineStep], forEntry id: UUID) throws -> [PipelineStep] {
    let target = folder(for: id)
    var made: [URL] = []
    func copy(_ reference: PluginImageRef) throws -> PluginImageRef {
      let source = URL(fileURLWithPath: reference.path)
      try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
      let ext = source.pathExtension
      let destination = target.appendingPathComponent(UUID().uuidString + (ext.isEmpty ? "" : "." + ext))
      try FileManager.default.copyItem(at: source, to: destination)
      made.append(destination)
      return PluginImageRef(name: reference.name, path: destination.path)
    }
    do {
      return try steps.map { step in
        var step = step
        step.moodboard = try step.moodboard?.map(copy)
        step.startImage = try step.startImage.map(copy)
        step.mask = try step.mask.map(copy)
        return step
      }
    } catch {
      for url in made { try? FileManager.default.removeItem(at: url) }
      throw error
    }
  }

  // MARK: Private

  private var fileURL: URL? { folder?.appendingPathComponent("queue.json") }

  private func load() {
    guard let fileURL, let data = try? Data(contentsOf: fileURL) else {
      entries = []
      return
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    // A file that cannot be read gives an empty queue; the pictures on disk are never touched for it.
    var loaded = (try? decoder.decode([QueueEntry].self, from: data)) ?? []
    let interrupted = loaded.contains { $0.status == .running }
    for index in loaded.indices where loaded[index].status == .running { loaded[index].status = .pending }
    entries = loaded
    if interrupted { save() }
  }

  private func save() {
    guard let fileURL else { return }
    do {
      try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      // `running` is never kept: it means the app was closed in the middle of it.
      let kept = entries.map { entry -> QueueEntry in
        var copy = entry
        if copy.status == .running { copy.status = .pending }
        return copy
      }
      try encoder.encode(kept).write(to: fileURL, options: .atomic)
    } catch {
      // A failed save only loses the queue at the next launch.
    }
  }
}
