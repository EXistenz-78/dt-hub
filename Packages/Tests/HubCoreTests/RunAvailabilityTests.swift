import HubKit
import Testing

@testable import HubCore

struct RunAvailabilityTests {
  @Test func connectedWithModelCanRun() {
    #expect(RunAvailability.blocker(connection: .connected, selectedModel: "flux_2_klein_9b_f16.ckpt") == nil)
  }

  @Test(arguments: [ConnectionStatus.disconnected, .connecting])
  func notConnectedBlocks(connection: ConnectionStatus) {
    #expect(RunAvailability.blocker(connection: connection, selectedModel: "flux_2_klein_9b_f16.ckpt") == .notConnected)
  }

  @Test(arguments: [String?.none, ""])
  func missingModelBlocks(model: String?) {
    #expect(RunAvailability.blocker(connection: .connected, selectedModel: model) == .noModelSelected)
  }

  @Test func connectionIsReportedBeforeModel() {
    #expect(RunAvailability.blocker(connection: .disconnected, selectedModel: nil) == .notConnected)
  }
}
