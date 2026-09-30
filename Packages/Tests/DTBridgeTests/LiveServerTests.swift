import Foundation
import HubKit
import Testing

@testable import DTBridge

/// Needs a real Draw Things gRPC server with "Model browsing" on. Run with:
/// `DTHUB_LIVE_DT=localhost:7859 swift test --filter LiveServerTests`
struct LiveServerTests {
  static let address = ProcessInfo.processInfo.environment["DTHUB_LIVE_DT"]

  @Test(.enabled(if: address != nil))
  func fetchesTheInstalledModels() async throws {
    let parts = try #require(Self.address?.split(separator: ":"))
    let backend = DrawThingsBackend(
      host: String(parts[0]), port: Int(parts[1]) ?? 7859, useTLS: true, sharedSecret: nil)
    let catalog = try await backend.fetchCatalog()
    await backend.shutdown()
    #expect(!catalog.models.isEmpty)
    #expect(catalog.models.allSatisfy { !$0.name.isEmpty })
  }

  @Test(.enabled(if: address != nil))
  func reportsAnUnreachableServer() async {
    let backend = DrawThingsBackend(host: "localhost", port: 1, useTLS: true, sharedSecret: nil)
    await #expect(throws: BackendError.self) { try await backend.fetchCatalog() }
    await backend.shutdown()
  }
}
