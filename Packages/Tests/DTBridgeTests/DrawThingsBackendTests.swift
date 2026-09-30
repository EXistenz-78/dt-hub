import Foundation
import HubKit
import Testing

@testable import DTBridge

/// Uses port 1 on this Mac, where nothing listens: the connection is refused at once.
struct DrawThingsBackendTests {
  /// A gRPC client that failed to connect retries on its own with a growing backoff (up to
  /// 2 minutes) and fails every call meanwhile. A fresh client per check after a failure
  /// keeps the reconnection within one check interval (spec §10).
  @Test func startsAFreshClientAfterAFailedCheck() async {
    let counter = ServiceCounter()
    let backend = DrawThingsBackend(host: "localhost", port: 1, useTLS: true, sharedSecret: nil) {
      counter.increment()
    }
    for _ in 0..<2 {
      await #expect(throws: BackendError.self) { try await backend.fetchCatalog() }
    }
    await backend.shutdown()
    #expect(counter.value == 2)
  }
}

final class ServiceCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  var value: Int { lock.withLock { count } }
  func increment() { lock.withLock { count += 1 } }
}
