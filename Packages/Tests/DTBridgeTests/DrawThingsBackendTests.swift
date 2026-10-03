import Foundation
import HubKit
import Testing

@testable import DTBridge

/// Uses port 1 on this Mac, where nothing listens: the connection is refused at once.
struct DrawThingsBackendTests {
  /// The start image of a Run goes to the server as an uncompressed 16-bit tensor, with the mask in the
  /// same message: 8192×8192 RGB is 384 MiB, over the client's default ceiling of 256 MiB.
  @Test func theClientAllowsMessagesBigEnoughForAnImageOf8192Pixels() {
    #expect(DrawThingsBackend.maxMessageBytes >= 8192 * 8192 * 3 * 2 + 64 * 1024 * 1024)
  }

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
