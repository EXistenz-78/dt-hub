import Foundation
import HubKit
import Testing

@testable import HubCore

/// The check `GenerationController.runPass` makes before it sends a pass (the controller is in the app target, out of
/// reach of the tests): the same calls in the same order, with a fake server that records what it is sent.
@MainActor
struct SeamlessPassCheckTests {
  let catalog = ModelCatalog(
    models: [CatalogModel(file: "krea_2.ckpt", name: "Krea 2", family: "krea_2")], loras: [], fileCount: 1)

  /// Runs a pass as `runPass` does: checked first, sent only when nothing refuses it.
  func run(
    _ step: PipelineStep, family: String, check: ((String?) -> String?)?
  ) async -> (session: GenerationSession, sent: [GenerationJob]) {
    let backend = FakeBackend(.success(catalog))
    await backend.setGeneration([.finished([testImage()])])
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(backend)
    let session = GenerationSession(store: MemoryImageStore())
    if !session.refusesSeamlessPass(step, family: family, check: check) {
      let batches = JobComposer.batches(
        prompt: "p", negativePrompt: "", model: "krea_2.ckpt", family: family, parameters: GenerationParameters(),
        catalog: catalog, seamlessTile: step.seamless) { 1 }
      session.start(batches, inputs: GenerationInputs(), backend: backend, monitor: monitor)
      await session.waitUntilFinished()
    }
    return (session, await backend.jobs)
  }

  @Test func aSeamlessPassWithoutTheCustomServerFailsAndNothingIsSent() async {
    let (session, sent) = await run(
      PipelineStep(seamless: .both), family: "krea_2", check: { SeamlessTile.problem(customServer: false, family: $0) })
    #expect(session.phase == .failed(.generationFailed("seamless: the custom server is not running.")))
    #expect(sent.isEmpty)
  }

  @Test func aSeamlessPassOnAnUnsupportedFamilyFailsAndNothingIsSent() async {
    let (session, sent) = await run(
      PipelineStep(seamless: .leftRight), family: "sdxl", check: { SeamlessTile.problem(customServer: true, family: $0) })
    #expect(session.phase == .failed(.generationFailed("seamless: this model family does not support it.")))
    #expect(sent.isEmpty)
  }

  @Test func anAllowedSeamlessPassIsSentWithItsTiling() async {
    let (session, sent) = await run(
      PipelineStep(seamless: .upDown), family: "krea_2", check: { SeamlessTile.problem(customServer: true, family: $0) })
    #expect(session.phase == .idle)
    #expect(sent.count == 1 && sent.first?.seamlessTile == .upDown)
  }

  @Test func aPassWithoutTilingIsNeverChecked() async {
    let (session, sent) = await run(PipelineStep(title: "plain"), family: "sdxl", check: { _ in "never" })
    #expect(session.phase == .idle)
    #expect(sent.count == 1 && sent.first?.seamlessTile == nil)
  }

  /// A queue entry puts its pipeline back with `setPipeline`, which does not check it: the check before the pass does,
  /// with the rule the registry wired (here the custom server is not running).
  @Test func aSeamlessPipelinePutBackByTheQueueFailsWithoutTheCustomServer() async throws {
    let root = PluginFixture.folder()
    let settingsFile = root.deletingLastPathComponent().appendingPathComponent("settings-\(root.lastPathComponent).json")
    let registry = PluginRegistry(
      folder: PluginFolder(root: root), settings: PluginSettingsStore(fileURL: settingsFile), loader: FakeLoader(),
      tempFolder: root)
    let target = FakeContributionTarget()
    registry.contributions.target = target
    registry.customServer = { false }
    let restored = PluginPipeline(name: "Seamless", steps: [PipelineStep(title: "Seamless", seamless: .both)])
    #expect(registry.contributions.setPipeline(restored, pluginID: "a"))
    let step = try #require(registry.contributions.pipeline?.pipeline.steps.first)
    let (session, sent) = await run(step, family: "krea_2", check: registry.contributions.seamlessProblem)
    #expect(session.phase == .failed(.generationFailed("seamless: the custom server is not running.")))
    #expect(sent.isEmpty)
    withExtendedLifetime(target) {}
  }
}
