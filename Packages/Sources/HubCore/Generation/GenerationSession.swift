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

  public private(set) var phase: Phase = .idle
  /// The latest preview while running; cleared when a RUN starts.
  public private(set) var preview: CGImage?
  /// Newest first.
  public private(set) var results: [GeneratedImage] = []

  @ObservationIgnored private let store: any ImageStore
  @ObservationIgnored private var task: Task<Void, Never>?

  public init(store: any ImageStore) {
    self.store = store
  }

  public var isRunning: Bool {
    if case .running = phase { return true }
    return false
  }

  /// Starts a RUN; ignored while one is running. The monitor's checks pause meanwhile.
  public func start(_ job: GenerationJob, backend: any GenerationBackend, monitor: ConnectionMonitor) {
    guard !isRunning else { return }
    phase = .running(step: nil, totalSteps: job.parameters.steps)
    preview = nil
    monitor.pause()
    task = Task {
      defer { monitor.resume() }
      do {
        for try await update in backend.generate(job) {
          switch update {
          case .progress(let step, let total):
            phase = .running(step: step, totalSteps: total)
          case .preview(let image):
            preview = image
          case .finished(let images):
            keep(images, of: job)
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

  /// Stop: cancels the RUN on the server; images already received are kept.
  public func cancel() {
    task?.cancel()
  }

  /// Waits for the current RUN to end (tests).
  public func waitUntilFinished() async {
    await task?.value
  }

  /// Hides a failure message.
  public func dismissFailure() {
    if case .failed = phase { phase = .idle }
  }

  private func keep(_ images: [CGImage], of job: GenerationJob) {
    let date = Date()
    for (index, image) in images.enumerated() {
      var url: URL?
      var saveError: String?
      do {
        url = try store.save(image, job: job, index: index, date: date)
      } catch {
        saveError = String(describing: error)
      }
      results.insert(
        GeneratedImage(image: image, job: job, date: date, fileURL: url, saveError: saveError), at: index)
    }
  }
}
