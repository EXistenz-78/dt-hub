import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
final class FakeQueueHost: QueueHost {
  var allowed = true
  /// What `restore` answers per prompt (nil = ok).
  var restoreProblems: [String: String] = [:]
  /// What `runAndWait` answers, in order.
  var outcomes: [QueueRunOutcome] = []
  private(set) var restored: [String] = []
  private(set) var runs = 0
  private(set) var stops = 0
  /// Runs while an entry is being restored (a test presses Stop here).
  var onRestore: (@MainActor () -> Void)?

  func canRun() -> Bool { allowed }
  func restore(_ entry: QueueEntry) async -> String? {
    restored.append(entry.preset.prompt)
    onRestore?()
    return restoreProblems[entry.preset.prompt]
  }
  func runAndWait() async -> QueueRunOutcome {
    runs += 1
    return outcomes.isEmpty ? .finished : outcomes.removeFirst()
  }
  func stop() { stops += 1 }
}

@MainActor
struct QueueRunnerTests {
  func make(_ prompts: [String], host: FakeQueueHost = FakeQueueHost()) -> (QueueStore, QueueRunner, FakeQueueHost) {
    let store = QueueStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent("QR-\(UUID())"))
    for prompt in prompts { store.add(QueueEntry(preset: Preset(name: "", prompt: prompt))) }
    return (store, QueueRunner(store: store, host: host), host)
  }

  func statuses(_ store: QueueStore) -> [QueueStatus] { store.entries.map(\.status) }

  @Test func runsAllPendingInOrder() async {
    let (store, runner, host) = make(["a", "b", "c"])
    await runner.run()
    #expect(statuses(store) == [.done, .done, .done])
    #expect(host.restored == ["a", "b", "c"])
    #expect(runner.state == .idle)
  }

  @Test func aFailedEntryGetsFailedAndTheQueueContinues() async {
    let host = FakeQueueHost()
    host.outcomes = [.finished, .failed("boom"), .finished]
    let (store, runner, _) = make(["a", "b", "c"], host: host)
    await runner.run()
    #expect(statuses(store) == [.done, .failed("boom"), .done])
  }

  @Test func anEntryThatCannotBeRestoredIsFailedAndSkipped() async {
    let host = FakeQueueHost()
    host.restoreProblems["b"] = "modello assente"
    let (store, runner, _) = make(["a", "b", "c"], host: host)
    await runner.run()
    #expect(statuses(store) == [.done, .failed("modello assente"), .done])
    #expect(host.runs == 2)
  }

  @Test func stopLeavesTheCurrentEntryPendingAndStops() async {
    let host = FakeQueueHost()
    host.outcomes = [.finished, .stopped]
    let (store, runner, _) = make(["a", "b", "c"], host: host)
    await runner.run()
    #expect(statuses(store) == [.done, .pending, .pending])
    #expect(runner.state == .idle)
  }

  @Test func emptyQueueSetsAMessage() async {
    let (_, runner, host) = make([])
    await runner.run()
    #expect(runner.message != nil)
    #expect(host.runs == 0)
  }

  @Test func cannotRunDoesNotStart() async {
    let host = FakeQueueHost()
    host.allowed = false
    let (store, runner, _) = make(["a"], host: host)
    await runner.run()
    #expect(runner.message != nil)
    #expect(statuses(store) == [.pending])
    #expect(host.restored.isEmpty)
  }

  @Test func finishedEntriesAreNotRunAgain() async {
    let (store, runner, host) = make(["a", "b"])
    store.setStatus(.done, for: store.entries[0].id)
    await runner.run()
    #expect(host.restored == ["b"])
  }

  @Test func stopDuringRestoreLeavesTheEntryPendingAndRunsNothing() async {
    let (store, runner, host) = make(["a", "b"])
    host.onRestore = { runner.stop() }
    await runner.run()
    #expect(statuses(store) == [.pending, .pending])
    #expect(host.runs == 0)
    #expect(runner.state == .idle)
  }

  @Test func stopAsksTheHostToStop() {
    let (_, runner, host) = make(["a"])
    runner.stop()
    #expect(host.stops == 1)
  }
}
