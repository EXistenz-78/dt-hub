import Foundation
import HubKit
import Observation

/// How the RUN of a queue entry ended.
public enum QueueRunOutcome: Equatable, Sendable {
  case finished
  case failed(String)
  /// The user pressed Stop.
  case stopped
}

/// What the queue needs from the app: put an entry on the tabs, run it, stop.
@MainActor
public protocol QueueHost: AnyObject {
  /// True when server, model and session allow a RUN.
  func canRun() -> Bool
  /// Puts the entry on Generation and Control; nil when done, otherwise why it could not be.
  func restore(_ entry: QueueEntry) async -> String?
  /// Presses RUN and returns when it, pipeline included, is over.
  func runAndWait() async -> QueueRunOutcome
  func stop()
}

/// Runs the pending entries of a `QueueStore` one after the other (queue design §3). A failed entry gets its mark and
/// the queue goes on; Stop ends the RUN and the queue, and the entry that was running stays pending.
@MainActor
@Observable
public final class QueueRunner {
  public enum State: Equatable, Sendable {
    case idle
    case running(UUID)
    case stopping
  }

  public enum Message: Equatable, Sendable {
    case noPending
    case cannotRun
  }

  public private(set) var state: State = .idle
  /// Something to tell the user after Start (nothing to run, or a RUN not possible now).
  public private(set) var message: Message?

  @ObservationIgnored private let store: QueueStore
  @ObservationIgnored private let host: any QueueHost
  @ObservationIgnored private var stopRequested = false
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var restoreTask: Task<String?, Never>?

  public init(store: QueueStore, host: any QueueHost) {
    self.store = store
    self.host = host
  }

  public var isRunning: Bool { state != .idle }

  /// Starts the loop in the background; ignored while it runs.
  public func start() {
    guard !isRunning else { return }
    task = Task { await run() }
  }

  /// Stops the RUN in progress and the queue.
  public func stop() {
    stopRequested = true
    if isRunning { state = .stopping }
    restoreTask?.cancel()
    host.stop()
  }

  /// The loop itself; `start()` runs it in a task.
  public func run() async {
    guard !isRunning else { return }
    message = nil
    stopRequested = false
    guard store.firstPending != nil else {
      message = .noPending
      return
    }
    guard host.canRun() else {
      message = .cannotRun
      return
    }
    while !stopRequested, let entry = store.firstPending {
      state = .running(entry.id)
      store.setStatus(.running, for: entry.id)
      // The restore runs in a task of its own so that Stop can end it: a plug-in that never answers must not hold the queue.
      let restoring = Task { await host.restore(entry) }
      restoreTask = restoring
      let problem = await restoring.value
      restoreTask = nil
      // Stop was pressed while the entry was being put on the tabs: whatever the restore said, nothing runs and the entry waits.
      if stopRequested {
        store.setStatus(.pending, for: entry.id)
        break
      }
      if let problem {
        store.setStatus(.failed(problem), for: entry.id)
        continue
      }
      switch await host.runAndWait() {
      case .finished: store.setStatus(.done, for: entry.id)
      case .failed(let reason): store.setStatus(.failed(reason), for: entry.id)
      case .stopped:
        store.setStatus(.pending, for: entry.id)
        stopRequested = true
      }
    }
    state = .idle
  }
}
