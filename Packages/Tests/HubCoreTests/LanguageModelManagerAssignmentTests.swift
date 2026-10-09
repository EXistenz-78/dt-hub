import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct LanguageModelManagerAssignmentTests {
  let helper = LanguageModelManagerTests()

  @Test func respondWithoutANameFollowsTheAssignments() async throws {
    let service = FakeLanguageModelService()
    let root = try helper.folder()
    let manager = helper.manager(service, root: root, selected: "text-model")
    manager.settings.selectedModel = ""
    manager.settings.assignments = [
      "vision-model": LanguageModelAssignment(family: .allOthers, use: .describe),
      "text-model": LanguageModelAssignment(family: .allOthers, use: .enhance),
    ]
    let image = root.appendingPathComponent("i.png")
    _ = try await manager.respond(to: "write")
    _ = try await manager.respond(to: "look", images: [image])
    #expect(await service.loads == ["text-model", "vision-model"])
  }

  @Test func nothingAssignedIsNoModelSelected() async throws {
    let service = FakeLanguageModelService()
    let manager = helper.manager(service, root: try helper.folder(), selected: "text-model")
    manager.settings.selectedModel = ""
    await #expect(throws: LanguageModelError.noModelSelected) { try await manager.respond(to: "hi") }
    #expect(manager.state == .failed(.noModelSelected))
  }

  @Test func reconcilingSavesTheAssignmentsAndTheOldChoiceIsConsumed() throws {
    let suite = "LanguageModelManagerAssignmentTests-\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    let store = LanguageModelSettingsStore(defaults: defaults, physicalMemory: 64 * 1_073_741_824)
    let root = try helper.folder()
    let manager = LanguageModelManager(service: FakeLanguageModelService(), store: store)
    manager.settings = LanguageModelSettings(
      folder: root.path, selectedModel: root.appendingPathComponent("vision-model").standardizedFileURL.path)
    manager.reconcileAssignments()
    let reread = LanguageModelSettingsStore(defaults: UserDefaults(suiteName: suite)!).load()
    #expect(reread.assignments["vision-model"] == LanguageModelAssignment(family: .allOthers, use: .both))
    #expect(reread.assignments["text-model"] == LanguageModelAssignment(family: .none, use: .both))
    #expect(reread.selectedModel.isEmpty)
  }

  @Test func theChosenModelIsUsedForTheFamilyOfTheButton() throws {
    let manager = helper.manager(FakeLanguageModelService(), root: try helper.folder(), selected: "vision-model")
    let result = manager.model(for: .describe, family: "flux2_9b")
    #expect((try? result.get())?.name == "vision-model")
    #expect(manager.model(for: .describe, family: nil).isSuccess)
  }
}

extension Result {
  fileprivate var isSuccess: Bool { if case .success = self { true } else { false } }
}
