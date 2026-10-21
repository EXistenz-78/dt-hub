import Foundation
import HubKit

/// What running one pass of a guided pipeline gave.
public enum PassOutcome: Equatable, Sendable {
  /// The picture the pass made (a file the plug-in can read) and its size.
  case made(URL, width: Int, height: Int)
  case stopped
  case failed(String)
}

/// How a guided pipeline ended.
public enum GuidedOutcome: Equatable, Sendable {
  case finished
  case stopped
  case failed(String)
  /// The plug-in did not answer (it went away, or took too long).
  case closed
}

/// Runs a pipeline the plug-in guides (spec §5, §6): for each pass it asks the plug-in (`session.next`), has the app run
/// the pass it got, and hands the result to the next question. It tells the plug-in how it ended (`session.end`) exactly
/// once. It knows nothing of the registry or the app: those come in as closures.
@MainActor
public final class GuidedSessionDriver {
  private let passes: Int
  private let tileLimit: Int
  private let ask: (Data) async -> Data?
  private let runPass: (PipelineStep, Int) async -> PassOutcome
  private let end: (Data) async -> Void
  private let progress: (Int, Int) -> Void

  /// `ask` sends a message to the plug-in and returns its answer (nil: none). `runPass` runs a pass (the second value is its
  /// 1-based index). `end` sends the closing message. `tileLimit` is the longest side a pass may have.
  public init(
    passes: Int, tileLimit: Int, ask: @escaping (Data) async -> Data?,
    runPass: @escaping (PipelineStep, Int) async -> PassOutcome, end: @escaping (Data) async -> Void,
    progress: @escaping (Int, Int) -> Void = { _, _ in }
  ) {
    self.passes = passes
    self.tileLimit = tileLimit
    self.ask = ask
    self.runPass = runPass
    self.end = end
    self.progress = progress
  }

  public func run() async -> GuidedOutcome {
    var previous: SessionPrevious?
    for index in 1...max(passes, 1) {
      if Task.isCancelled { return await finish(.stopped, reason: .stopped) }
      progress(index, passes)
      let answer = await ask(SessionNextRequest(index: index, count: passes, previous: previous).data())
      if Task.isCancelled { return await finish(.stopped, reason: .stopped) }
      guard answer != nil else { return await finish(.closed, reason: .closed) }
      switch SessionAnswer.parse(answer, tileLimit: tileLimit) {
      case .done:
        return await finish(.finished, reason: .finished)
      case .invalid(let reason):
        return await finish(.failed(reason), reason: .failed)
      case .pass(let step):
        switch await runPass(step, index) {
        case .made(let url, let width, let height):
          previous = SessionPrevious(path: url.path, width: width, height: height)
        case .stopped:
          return await finish(.stopped, reason: .stopped)
        case .failed(let reason):
          return await finish(.failed(reason), reason: .failed)
        }
      }
    }
    // Every declared pass ran and the plug-in was not asked again: the last result goes with the closing message.
    return await finish(.finished, reason: .finished, previous: previous)
  }

  private func finish(
    _ outcome: GuidedOutcome, reason: PluginSessionReason, previous: SessionPrevious? = nil
  ) async -> GuidedOutcome {
    await end(PluginSession.endMessage(reason, previous: previous))
    return outcome
  }
}
