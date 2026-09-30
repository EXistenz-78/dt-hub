import HubKit
import Testing

@testable import HubCore

@MainActor
struct ConnectionMonitorTests {
  let catalogA = ModelCatalog(
    models: [CatalogModel(file: "a.ckpt", name: "A", family: "flux2_9b")], loras: [], fileCount: 1)
  let catalogB = ModelCatalog(
    models: [CatalogModel(file: "b.ckpt", name: "B", family: "z_image")], loras: [], fileCount: 1)

  @Test func startsDisconnectedWithAnEmptyCatalog() async {
    let monitor = ConnectionMonitor()
    await monitor.refresh()
    #expect(monitor.status == .disconnected)
    #expect(monitor.catalog == .empty)
  }

  @Test func connectsAndLoadsTheCatalog() async {
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(FakeBackend(.success(catalogA)))
    #expect(monitor.status == .connected)
    #expect(monitor.catalog == catalogA)
    #expect(monitor.lastError == nil)
  }

  @Test(arguments: [BackendError.unreachable("refused"), .unauthorized])
  func reportsFailures(error: BackendError) async {
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(FakeBackend(.failure(error)))
    #expect(monitor.status == .disconnected)
    #expect(monitor.lastError == error)
  }

  @Test func losingTheServerClearsTheCatalog() async {
    let backend = FakeBackend(.success(catalogA))
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(backend)
    await backend.setResult(.failure(.unreachable("gone")))
    await monitor.refresh()
    #expect(monitor.status == .disconnected)
    #expect(monitor.catalog == .empty)
  }

  @Test func reconnectsWhenTheServerComesBack() async {
    let backend = FakeBackend(.failure(.unreachable("down")))
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(backend)
    await backend.setResult(.success(catalogA))
    await monitor.refresh()
    #expect(monitor.status == .connected)
    #expect(monitor.lastError == nil)
  }

  @Test func replacingTheBackendShutsTheOldOneDown() async {
    let old = FakeBackend(.success(catalogA))
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(old)
    await monitor.replaceBackend(FakeBackend(.success(catalogB)))
    #expect(await old.didShutDown)
    #expect(monitor.catalog == catalogB)
  }

  @Test func invalidSettingsLeaveItDisconnected() async {
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(FakeBackend(.success(catalogA)))
    await monitor.replaceBackend(nil)
    #expect(monitor.status == .disconnected)
    #expect(monitor.catalog == .empty)
  }

  @Test func showsConnectingWhileTheFirstCheckRuns() async throws {
    let monitor = ConnectionMonitor()
    let check = Task { await monitor.replaceBackend(FakeBackend(.success(catalogA), delay: .milliseconds(300))) }
    try await Task.sleep(for: .milliseconds(100))
    #expect(monitor.status == .connecting)
    await check.value
    #expect(monitor.status == .connected)
  }

  @Test func staysConnectedDuringAPeriodicCheck() async throws {
    let backend = FakeBackend(.success(catalogA), delay: .milliseconds(300))
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(backend)
    let check = Task { await monitor.refresh() }
    try await Task.sleep(for: .milliseconds(100))
    #expect(monitor.status == .connected)
    await check.value
  }

  @Test func ignoresAReplyFromAReplacedBackend() async throws {
    let monitor = ConnectionMonitor()
    let slow = Task { await monitor.replaceBackend(FakeBackend(.success(catalogA), delay: .milliseconds(300))) }
    try await Task.sleep(for: .milliseconds(100))
    await monitor.replaceBackend(FakeBackend(.success(catalogB)))
    await slow.value
    #expect(monitor.catalog == catalogB)
    #expect(monitor.status == .connected)
  }

  @Test func runChecksAfterEachIntervalUntilCancelled() async {
    let backend = FakeBackend(.success(catalogA))
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(backend)
    let sleeps = SleepCounter(stopAfter: 3)
    await monitor.run(every: .seconds(5)) { _ in try await sleeps.tick() }
    // replaceBackend checked once, then one check after each of the two completed sleeps.
    #expect(await backend.fetchCount == 3)
  }
}

/// A `sleep` stand-in that returns immediately and throws (like a cancelled task) on call `stopAfter`.
actor SleepCounter {
  private let stopAfter: Int
  private var calls = 0

  init(stopAfter: Int) { self.stopAfter = stopAfter }

  func tick() throws {
    calls += 1
    if calls >= stopAfter { throw CancellationError() }
  }
}
