import HubKit
import Testing

@testable import HubCore

struct RunAvailabilityTests {
  let klein = "flux_2_klein_9b_f16.ckpt"
  var catalog: ModelCatalog {
    ModelCatalog(models: [CatalogModel(file: klein, name: "FLUX.2 [klein] 9B", family: "flux2_9b")], loras: [], fileCount: 1)
  }

  @Test func connectedWithInstalledModelCanRun() {
    #expect(RunAvailability.blocker(connection: .connected, selectedModel: klein, catalog: catalog) == nil)
  }

  @Test(arguments: [ConnectionStatus.disconnected, .connecting])
  func notConnectedBlocks(connection: ConnectionStatus) {
    #expect(RunAvailability.blocker(connection: connection, selectedModel: klein, catalog: catalog) == .notConnected)
  }

  @Test(arguments: [String?.none, ""])
  func missingModelBlocks(model: String?) {
    #expect(RunAvailability.blocker(connection: .connected, selectedModel: model, catalog: catalog) == .noModelSelected)
  }

  @Test func connectionIsReportedBeforeModel() {
    #expect(RunAvailability.blocker(connection: .disconnected, selectedModel: nil, catalog: .empty) == .notConnected)
  }

  @Test func modelMissingFromServerBlocks() {
    #expect(
      RunAvailability.blocker(connection: .connected, selectedModel: "gone.ckpt", catalog: catalog)
        == .modelNotOnServer)
  }
}
