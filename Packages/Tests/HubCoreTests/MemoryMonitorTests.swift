import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct MemoryMonitorTests {
  nonisolated let gb: UInt64 = 1_073_741_824

  nonisolated func snapshot(available: UInt64 = 30, server: UInt64? = 20) -> MemorySnapshot {
    MemorySnapshot(
      totalBytes: 64 * gb, availableBytes: available * gb, appBytes: 2 * gb, serverBytes: server.map { $0 * gb },
      swapUsedBytes: 0, pressure: .normal)
  }

  /// Records what the sampler was asked.
  final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var pids: [Int32?] = []
    var all: [Int32?] { lock.withLock { pids } }
    func add(_ pid: Int32?) { lock.withLock { pids.append(pid) } }
  }

  @Test func aRefreshPublishesTheReading() async {
    let monitor = MemoryMonitor(
      sampler: MemorySampler(sample: { _ in self.snapshot() }, findServer: { nil }), serverPid: { nil })
    #expect(monitor.snapshot == nil)
    await monitor.refresh()
    #expect(monitor.snapshot == snapshot())
  }

  @Test func aReadingThatLooksTheSameIsNotPublishedAgain() async {
    let monitor = MemoryMonitor(
      sampler: MemorySampler(
        sample: { _ in
          var s = self.snapshot()
          s.availableBytes += UInt64.random(in: 0..<10_000_000)  // under a tenth of a GB
          return s
        }, findServer: { nil }),
      serverPid: { nil })
    for _ in 0..<5 { await monitor.refresh() }
    #expect(monitor.publications == 1)
  }

  @Test func aReadingThatChangesIsPublished() async {
    let box = Calls()
    let monitor = MemoryMonitor(
      sampler: MemorySampler(
        sample: { _ in
          box.add(nil)
          return self.snapshot(available: UInt64(box.all.count) * 5)
        }, findServer: { nil }),
      serverPid: { nil })
    await monitor.refresh()
    await monitor.refresh()
    #expect(monitor.publications == 2)
  }

  @Test func theManagedServerPidIsUsedAndTheFinderIsNotAsked() async {
    let calls = Calls()
    let monitor = MemoryMonitor(
      sampler: MemorySampler(sample: { pid in calls.add(pid); return self.snapshot() }, findServer: { Issue.record("not needed"); return nil }),
      serverPid: { 4321 })
    await monitor.refresh()
    #expect(calls.all == [4321])
  }

  @Test func withoutAManagedServerTheFinderIsUsedAndRememberedWhileItWorks() async {
    let calls = Calls()
    let finds = Calls()
    let monitor = MemoryMonitor(
      sampler: MemorySampler(
        sample: { pid in calls.add(pid); return self.snapshot() }, findServer: { finds.add(777); return 777 }),
      serverPid: { nil })
    await monitor.refresh()
    await monitor.refresh()
    #expect(calls.all == [777, 777])
    #expect(finds.all.count == 1)
  }

  @Test func aServerThatIsGoneIsFoundAgain() async {
    let calls = Calls()
    let finds = Calls()
    let monitor = MemoryMonitor(
      sampler: MemorySampler(
        sample: { pid in calls.add(pid); return self.snapshot(server: calls.all.count == 1 ? nil : 20) },
        findServer: { finds.add(1); return 777 }),
      serverPid: { nil })
    await monitor.refresh()  // finds 777, the server is gone: no server bytes
    await monitor.refresh()  // asks the finder again
    #expect(finds.all.count == 2)
  }

  @Test func runSamplesEveryIntervalUntilItIsCancelled() async {
    let calls = Calls()
    let monitor = MemoryMonitor(
      sampler: MemorySampler(sample: { _ in calls.add(nil); return self.snapshot() }, findServer: { nil }), serverPid: { nil })
    let task = Task { @MainActor in
      await monitor.run(every: .seconds(1), sleep: { _ in try await Task.sleep(for: .milliseconds(5)) })
    }
    while calls.all.count < 3 { try? await Task.sleep(for: .milliseconds(5)) }
    task.cancel()
    await task.value
    let after = calls.all.count
    try? await Task.sleep(for: .milliseconds(40))
    #expect(calls.all.count == after)
  }

  @Test func liveReadingsAreSane() {
    let live = MemorySampler.live.sample(nil)
    #expect(live != nil)
    if let live {
      #expect(live.totalBytes > 0)
      #expect(live.availableBytes <= live.totalBytes)
      #expect(live.appBytes > 0)
    }
  }
}
