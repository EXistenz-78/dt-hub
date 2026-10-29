import CoreGraphics
import DrawThingsClient
import Foundation
import HubKit
import Testing

@testable import DTBridge

struct VideoStreamToolsTests {
  func frame() -> CGImage { TestImages.make(width: 8, height: 8)! }

  struct Boom: Error {}

  /// A fake stream: the events, then the error (if any).
  func stream(_ events: [GenerationEvent], failingWith error: (any Error)? = nil)
    -> AsyncThrowingStream<GenerationEvent, any Error>
  {
    AsyncThrowingStream { continuation in
      for event in events { continuation.yield(event) }
      continuation.finish(throwing: error)
    }
  }

  final class Recorder: @unchecked Sendable {
    var opened = 0
    var slept: [Duration] = []
    var seen = 0
  }

  // How the library surfaces gRPC errors: INTERNAL as .server(code: "internalError"), UNAVAILABLE as .connectionFailed.
  @Test func retryableErrors() {
    #expect(VideoStreamTools.isRetryable(DrawThingsError.server(code: "internalError", message: "x")))
    #expect(VideoStreamTools.isRetryable(DrawThingsError.connectionFailed("unavailable")))
    #expect(!VideoStreamTools.isRetryable(CancellationError()))
    #expect(!VideoStreamTools.isRetryable(BackendError.unauthorized))
    #expect(!VideoStreamTools.isRetryable(DrawThingsError.unauthenticated))
    #expect(!VideoStreamTools.isRetryable(DrawThingsError.server(code: "invalidArgument", message: "x")))
    #expect(!VideoStreamTools.isRetryable(DrawThingsError.invalidConfiguration(field: "a", reason: "b")))
  }

  @Test func accumulatorBuildsAPartialVideo() throws {
    var accumulator = VideoStreamTools.Accumulator()
    accumulator.add(frame())
    #expect(accumulator.partialVideo(framesPerSecond: 24) == nil)
    accumulator.add(frame())
    accumulator.add(frame())
    let video = try #require(accumulator.partialVideo(framesPerSecond: 24))
    #expect(video.frames.count == 3)
    #expect(video.isPartial)
    #expect(video.framesPerSecond == 24)
  }

  @Test func retryDelayIsHalfASecond() {
    #expect(VideoStreamTools.retryDelay == .milliseconds(500))
  }

  @Test func retriesOnceWhenNoFrameArrived() async throws {
    let recorder = Recorder()
    let partial = try await VideoStreamTools.consume(
      open: {
        recorder.opened += 1
        return recorder.opened == 1
          ? stream([], failingWith: DrawThingsError.server(code: "internalError", message: "x"))
          : stream([.image(frame(), index: 0)])
      },
      framesPerSecond: 24, sleep: { recorder.slept.append($0) }, onEvent: { _ in recorder.seen += 1 })
    #expect(recorder.opened == 2)
    #expect(recorder.slept == [.milliseconds(500)])
    #expect(recorder.seen == 1)
    #expect(partial == nil)
  }

  @Test func secondFailureWithoutFramesThrows() async {
    let recorder = Recorder()
    await #expect(throws: DrawThingsError.self) {
      _ = try await VideoStreamTools.consume(
        open: {
          recorder.opened += 1
          return stream([], failingWith: DrawThingsError.connectionFailed("down"))
        },
        framesPerSecond: 24, sleep: { _ in }, onEvent: { _ in })
    }
    #expect(recorder.opened == 2)
  }

  @Test func errorAfterFramesGivesPartialWithoutRetry() async throws {
    let recorder = Recorder()
    let partial = try await VideoStreamTools.consume(
      open: {
        recorder.opened += 1
        return stream(
          [.image(frame(), index: 0), .image(frame(), index: 1)],
          failingWith: DrawThingsError.server(code: "internalError", message: "x"))
      },
      framesPerSecond: 16, sleep: { recorder.slept.append($0) }, onEvent: { _ in })
    #expect(recorder.opened == 1)
    #expect(recorder.slept.isEmpty)
    #expect(partial?.frames.count == 2)
    #expect(partial?.isPartial == true)
    #expect(partial?.framesPerSecond == 16)
  }

  @Test func oneFrameThenErrorThrows() async {
    await #expect(throws: DrawThingsError.self) {
      _ = try await VideoStreamTools.consume(
        open: { stream([.image(frame(), index: 0)], failingWith: DrawThingsError.server(code: "internalError", message: "x")) },
        framesPerSecond: 24, sleep: { _ in }, onEvent: { _ in })
    }
  }

  @Test func cancellationNeverSavesNorRetries() async {
    let recorder = Recorder()
    await #expect(throws: CancellationError.self) {
      _ = try await VideoStreamTools.consume(
        open: {
          recorder.opened += 1
          return stream(
            [.image(frame(), index: 0), .image(frame(), index: 1)], failingWith: CancellationError())
        },
        framesPerSecond: 24, sleep: { _ in }, onEvent: { _ in })
    }
    #expect(recorder.opened == 1)
  }

  @Test func handlerErrorsPassThroughEvenWithFrames() async {
    await #expect(throws: BackendError.self) {
      _ = try await VideoStreamTools.consume(
        open: { stream([.image(frame(), index: 0), .image(frame(), index: 1), .image(frame(), index: 2)]) },
        framesPerSecond: 24, sleep: { _ in },
        onEvent: { _ in throw BackendError.noImages })
    }
  }
}
