import CoreGraphics
import Foundation
import HubKit
import Observation

/// One image of the session strip (spec §7), with the job that made it.
public struct GeneratedImage: Identifiable, Sendable {
  public let id = UUID()
  public let image: CGImage
  public let job: GenerationJob
  public let date: Date
  /// nil when saving failed; `saveError` says why.
  public let fileURL: URL?
  public let saveError: String?
  /// Seconds the image took to make (the time of its generation call, shared by the images of one call);
  /// nil for a picture saved before the time was kept.
  public var elapsed: TimeInterval?
  /// True for a picture read back from its file at launch: `image` is a small version of it.
  public var isRestored = false
}

/// Runs generations, one at a time: progress, live preview, results, Stop (spec §7, §10).
@MainActor
@Observable
public final class GenerationSession {
  public enum Phase: Equatable, Sendable {
    case idle
    /// `step` is nil while the server encodes the prompt or decodes the image.
    case running(step: Int?, totalSteps: Int)
    case failed(BackendError)
  }

  /// Which batch of the RUN is running (1-based).
  public struct Batch: Equatable, Sendable {
    public let index: Int
    public let count: Int
    public init(index: Int, count: Int) {
      self.index = index
      self.count = count
    }
  }

  public private(set) var phase: Phase = .idle
  public private(set) var batch = Batch(index: 1, count: 1)
  /// The latest preview while running; cleared when a RUN starts.
  public private(set) var preview: CGImage?
  /// Newest first.
  public private(set) var results: [GeneratedImage] = []

  @ObservationIgnored private let store: any ImageStore
  @ObservationIgnored private var history: ResultsHistoryStore?
  @ObservationIgnored private var task: Task<Void, Never>?

  /// Longest side of the pictures read back at launch.
  public nonisolated static let restoredThumbnailSize = 512
  /// The longest side a saved result is kept at in memory for the strip and the preview: the screen
  /// needs no more, and an 8192-pixel image (Tiled Diffusion) is 256 MiB. The file keeps the original.
  public nonisolated static let displayPixels = 2048

  /// With a `history`, the strip survives the app: it is saved after every RUN and read back by
  /// `restoreHistory`.
  public init(store: any ImageStore, history: ResultsHistoryStore? = nil) {
    self.store = store
    self.history = history
  }

  public var isRunning: Bool {
    if case .running = phase { return true }
    return false
  }

  /// Starts a RUN of one job; ignored while one is running.
  public func start(_ job: GenerationJob, backend: any GenerationBackend, monitor: ConnectionMonitor) {
    start([job], backend: backend, monitor: monitor)
  }

  /// Starts a RUN made of batches, run one after the other (see `batchesForRun`); ignored
  /// while one is running. The monitor's checks pause meanwhile. Every batch gets the same
  /// `inputs` (the Control tab's images).
  public func start(
    _ batches: [GenerationJob], inputs: GenerationInputs = .none, backend: any GenerationBackend,
    monitor: ConnectionMonitor
  ) {
    guard !isRunning, let first = batches.first else { return }
    phase = .running(step: nil, totalSteps: first.parameters.steps)
    batch = Batch(index: 1, count: batches.count)
    preview = nil
    monitor.pause()
    let store = store
    task = Task {
      defer { monitor.resume() }
      do {
        for (number, job) in batches.enumerated() {
          try Task.checkCancellation()
          batch = Batch(index: number + 1, count: batches.count)
          phase = .running(step: nil, totalSteps: job.parameters.steps)
          var began = ContinuousClock.now
          for try await update in backend.generate(job, inputs: inputs) {
            switch update {
            case .progress(let step, let total):
              phase = .running(step: step, totalSteps: total)
            case .preview(let image):
              preview = image
            case .finished(let images):
              let took = began.duration(to: .now)
              began = .now
              let seconds = Double(took.components.seconds) + Double(took.components.attoseconds) / 1e18
              let saved = await Self.save(images, of: job, elapsed: seconds / Double(max(images.count, 1)), in: store)
              results.insert(contentsOf: saved, at: 0)
              persistHistory()
            }
          }
        }
        phase = .idle
      } catch is CancellationError {
        phase = .idle
      } catch {
        phase = .failed(error as? BackendError ?? .generationFailed(String(describing: error)))
      }
      task = nil
    }
  }

  /// Stop: cancels the RUN on the server; the batches already finished are kept, the one
  /// running is lost (Draw Things sends its images only at the end).
  public func cancel() {
    task?.cancel()
  }

  /// Waits for the current RUN to end (tests).
  public func waitUntilFinished() async {
    await task?.value
  }

  /// Shows a failure for a RUN that could not start (its inputs could not be prepared).
  public func fail(with error: BackendError) {
    guard !isRunning else { return }
    phase = .failed(error)
  }

  /// Brings back the strip of the last launches: the saved results that are still on disk and
  /// still carry their job, small and away from the main actor. What is already in the strip
  /// (a RUN that finished meanwhile) stays ahead and is not listed twice.
  public func restoreHistory() async {
    guard let history else { return }
    let entries = history.load()
    let restored = await Task.detached(priority: .utility) {
      entries.compactMap { Self.restoredImage($0) }
    }.value
    // The project may have changed while the pictures were read: they belong to the old strip then.
    guard self.history?.fileURL == history.fileURL else { return }
    let present = Set(results.compactMap(\.fileURL))
    results.append(contentsOf: restored.filter { $0.fileURL.map { !present.contains($0) } ?? false })
  }

  /// The strip of another project: empties the strip, takes that project's list and reads its pictures back. Refused
  /// while a RUN is under way (the RUN would be listed in the wrong project).
  public func switchHistory(to history: ResultsHistoryStore?) async {
    guard !isRunning else { return }
    results = []
    self.history = history
    await restoreHistory()
  }

  private nonisolated static func restoredImage(_ entry: ResultsHistoryEntry) -> GeneratedImage? {
    let url = URL(fileURLWithPath: entry.path)
    guard let job = PNGImageStore.job(in: url),
      let image = PNGImageStore.image(at: url, maxPixel: restoredThumbnailSize)
    else { return nil }
    return GeneratedImage(
      image: image, job: job, date: entry.date, fileURL: url, saveError: nil, elapsed: PNGImageStore.elapsed(in: url),
      isRestored: true)
  }

  /// Writes the strip's files, newest first, keeping the older entries not read back yet (but not
  /// the `removed` ones).
  private func persistHistory(removing removed: Set<String> = []) {
    guard let history else { return }
    let current = results.compactMap { result in
      result.fileURL.map { ResultsHistoryEntry(path: $0.path, date: result.date) }
    }
    let listed = Set(current.map(\.path))
    history.save(current + history.load().filter { !listed.contains($0.path) && !removed.contains($0.path) })
  }

  /// Takes the images out of the strip and moves their files to the Trash. An image that was never
  /// saved only leaves the strip. A file the Trash refuses stays in the strip; the reasons come back,
  /// one per file. The history file forgets what went.
  @discardableResult
  public func remove(_ ids: Set<GeneratedImage.ID>) -> [String] {
    var failures: [String] = []
    var gone: Set<GeneratedImage.ID> = []
    var removedPaths: Set<String> = []
    for result in results where ids.contains(result.id) {
      guard let url = result.fileURL else {
        gone.insert(result.id)
        continue
      }
      do {
        try store.trash(url)
        gone.insert(result.id)
        removedPaths.insert(url.path)
      } catch {
        failures.append("\(url.lastPathComponent): \((error as? ImageStoreError).map(Self.describe) ?? error.localizedDescription)")
      }
    }
    guard !gone.isEmpty else { return failures }
    results.removeAll { gone.contains($0.id) }
    persistHistory(removing: removedPaths)
    return failures
  }

  private nonisolated static func describe(_ error: ImageStoreError) -> String {
    switch error {
    case .cannotWrite(let reason), .cannotTrash(let reason): reason
    }
  }

  /// Hides a failure message.
  public func dismissFailure() {
    if case .failed = phase { phase = .idle }
  }

  /// Encodes and writes the images away from the main actor; an image that cannot be saved
  /// is kept with the reason.
  private nonisolated static func save(
    _ images: [CGImage], of job: GenerationJob, elapsed: TimeInterval, in store: any ImageStore
  ) async -> [GeneratedImage] {
    await Task.detached(priority: .userInitiated) {
      let date = Date()
      return images.enumerated().map { index, image in
        do {
          let url = try store.save(image, job: job, index: index, date: date, elapsed: elapsed)
          return GeneratedImage(
            image: reduced(image, to: displayPixels), job: job, date: date, fileURL: url, saveError: nil,
            elapsed: elapsed)
        } catch {
          return GeneratedImage(image: image, job: job, date: date, fileURL: nil, saveError: String(describing: error), elapsed: elapsed)
        }
      }
    }.value
  }

  /// The image scaled so that its long side is at most `maxPixel`; the same image when it is smaller
  /// already (or cannot be scaled).
  nonisolated static func reduced(_ image: CGImage, to maxPixel: Int) -> CGImage {
    let long = max(image.width, image.height)
    guard long > maxPixel else { return image }
    let scale = Double(maxPixel) / Double(long)
    let width = max(1, Int((Double(image.width) * scale).rounded()))
    let height = max(1, Int((Double(image.height) * scale).rounded()))
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ?? CGContext(
          data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return image }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage() ?? image
  }
}
