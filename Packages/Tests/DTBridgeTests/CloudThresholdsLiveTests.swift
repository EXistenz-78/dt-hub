import DrawThingsClient
import Foundation
import Testing

@testable import DTBridge

/// Needs the network (the cloud's server, no account). Run outside the sandbox with:
/// `DTHUB_LIVE_CLOUD=1 swift test --filter CloudThresholdsLiveTests`
struct CloudThresholdsLiveTests {
  static let enabled = ProcessInfo.processInfo.environment["DTHUB_LIVE_CLOUD"] == "1"

  @Test(.enabled(if: enabled))
  func echoOfTheCloudHasThresholdsOnlyWithAnActivePolicy() async throws {
    let service = DrawThingsService(
      endpoint: CloudCatalog.server,
      options: ConnectionOptions(
        security: .tls(), sharedSecret: nil, requestTimeout: .seconds(10), modelSpecs: .bundled))
    let reply = try await service.echo(name: "DT Hub")
    await service.shutdown()
    print(
      "CLOUD-THRESHOLDS hasThresholds=\(reply.hasThresholds) plus=\(reply.thresholds.plus) community=\(reply.thresholds.community) expireAt=\(reply.thresholds.expireAt)"
    )
    // The server fills `thresholds` only while a temporary compute-unit policy is active (15 Oct 2026: none was).
    #expect(!reply.hasThresholds || reply.thresholds.plus > 0)
  }
}
