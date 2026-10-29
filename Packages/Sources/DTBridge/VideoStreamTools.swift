import CoreGraphics
import DrawThingsClient
import Foundation
import HubKit

/// What a video job needs on top of the plain image stream: the frames received so far, the retry of a stream that
/// failed before sending anything, and the partial video when it fails later.
enum VideoStreamTools {
  /// The pause before the single retry.
  static let retryDelay: Duration = .milliseconds(500)

  /// A gRPC INTERNAL or UNAVAILABLE failure, as the library surfaces them: INTERNAL arrives as
  /// `.server(code: "internalError")`, UNAVAILABLE (and DEADLINE_EXCEEDED) as `.connectionFailed`.
  static func isRetryable(_ error: any Error) -> Bool {
    guard let error = error as? DrawThingsError else { return false }
    switch error {
    case .connectionFailed: return true
    case .server(let code, _): return code.lowercased() == "internalerror" || code.lowercased() == "internal"
    default: return false
    }
  }

  /// The frames of a video, in arrival order.
  struct Accumulator {
    private(set) var frames: [CGImage] = []

    var count: Int { frames.count }

    mutating func add(_ image: CGImage) { frames.append(image) }

    /// What arrived, as a partial video; nil when it is not enough for a clip (fewer than 2 frames).
    func partialVideo(framesPerSecond: Double) -> GeneratedVideo? {
      guard frames.count >= 2 else { return nil }
      return GeneratedVideo(frames: frames, audio: nil, framesPerSecond: framesPerSecond, isPartial: true)
    }
  }

  /// Runs a video stream: every event goes to `onEvent`, the `.image` ones are also collected.
  /// - A retryable failure with no frame received opens the stream once more, after `retryDelay`.
  /// - A failure after at least 2 frames returns the partial video instead of throwing; a retryable one never
  ///   triggers a second attempt then.
  /// - Cancellation, errors thrown by `onEvent` and any other failure propagate: nothing is saved.
  /// - Returns: the partial video, or nil when the stream ended normally.
  static func consume<S: AsyncSequence>(
    open: () throws -> S, framesPerSecond: Double,
    sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    onEvent: (GenerationEvent) throws -> Void
  ) async throws -> GeneratedVideo? where S.Element == GenerationEvent {
    var accumulator = Accumulator()
    var retried = false
    while true {
      var handlerError: (any Error)?
      do {
        for try await event in try open() {
          if case .image(let image, _) = event { accumulator.add(image) }
          do { try onEvent(event) } catch {
            handlerError = error
            throw error
          }
        }
        return nil
      } catch {
        if let handlerError { throw handlerError }
        if error is CancellationError || Task.isCancelled { throw error }
        if accumulator.count == 0, !retried, isRetryable(error) {
          retried = true
          try await sleep(retryDelay)
          continue
        }
        if let partial = accumulator.partialVideo(framesPerSecond: framesPerSecond) { return partial }
        throw error
      }
    }
  }
}
