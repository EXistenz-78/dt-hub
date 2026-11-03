import Foundation
import HubKit
import Testing

@testable import HubCore

/// LM Studio's server, never really asked.
actor FakeServerService: ServerLanguageModelService {
  private(set) var listed: [LanguageModelDescriptor] = []
  private(set) var listError: LanguageModelError?
  private(set) var loads: [String] = []
  private(set) var unloads = 0
  private(set) var configured: [(URL, Set<String>)] = []

  func offer(_ names: [String]) { listed = names.map { ServerModelList.descriptor(id: $0, vision: false) } }
  func fail(with error: LanguageModelError?) { listError = error }

  func configure(address: URL, visionModels: Set<String>) { configured.append((address, visionModels)) }
  func models() async throws -> [LanguageModelDescriptor] {
    if let listError { throw listError }
    return listed
  }
  func load(_ model: LanguageModelDescriptor) async throws { loads.append(model.name) }
  func unload() async { unloads += 1 }
  func respond(to prompt: String, images: [URL], options: LanguageModelOptions, history: [LanguageModelTurn]) async throws
    -> String
  { "server answer" }
}

final class ReleaseCount {
  var count = 0
}

@MainActor
struct LanguageModelManagerServerTests {
  let helper = LanguageModelManagerTests()
  static let address = "http://localhost:1235/v1"

  func make(
    mlx: FakeLanguageModelService = FakeLanguageModelService(), server: FakeServerService, root: URL? = nil,
    backend: LanguageModelBackend = .lmStudio, serverURL: String = address, available: Int64 = 1_000_000,
    idle: Int = 10, freeAtRun: Bool = false, freeImage: Bool = false, release: @escaping @MainActor () async -> Void = {}
  ) throws -> LanguageModelManager {
    let defaults = UserDefaults(suiteName: "LanguageModelManagerServerTests-\(UUID())")!
    let store = LanguageModelSettingsStore(defaults: defaults, physicalMemory: 64 * 1_073_741_824)
    let manager = LanguageModelManager(
      service: mlx, store: store, memory: MemoryProbe { available }, minute: .milliseconds(40),
      releaseImageModel: release, isImageModelBusy: { false }, serverService: server)
    manager.settings = LanguageModelSettings(
      folder: (try root ?? helper.folder()).path, selectedModel: "", freeAtRun: freeAtRun,
      freeImageModelForLanguageModel: freeImage, idleMinutes: idle, backend: backend, serverURL: serverURL)
    return manager
  }

  let both = LanguageModelAssignment(family: .allOthers, use: .both)

  @Test func serverBackendListsTheServerModelsAfterARefresh() async throws {
    let server = FakeServerService()
    await server.offer(["a", "v"])
    let manager = try make(server: server)
    #expect(manager.availableModels().isEmpty)
    await manager.refreshServerModels()
    #expect(manager.availableModels().map(\.name) == ["a", "v"])
    let configured = await server.configured
    #expect(configured.first?.0.absoluteString == Self.address)
  }

  @Test func aQuestionGoesToTheServerServiceNotToMLX() async throws {
    let server = FakeServerService()
    let mlx = FakeLanguageModelService()
    await server.offer(["a", "v"])
    let manager = try make(mlx: mlx, server: server)
    await manager.refreshServerModels()
    manager.settings.assignments["a"] = both
    let answer = try await manager.respond(to: "write")
    #expect(answer == "server answer")
    #expect(await server.loads == ["a"])
    #expect(await mlx.loads.isEmpty)
  }

  @Test func theMemoryCheckNeverBlocksAServerModel() async throws {
    let server = FakeServerService()
    await server.offer(["a"])
    let manager = try make(server: server, available: 0)
    await manager.refreshServerModels()
    manager.settings.assignments["a"] = both
    _ = try await manager.respond(to: "write")
    #expect(await server.loads == ["a"])
  }

  @Test func theServerModelIsNotUnloadedByIdleOrRun() async throws {
    let server = FakeServerService()
    await server.offer(["a"])
    let manager = try make(server: server, idle: 1, freeAtRun: true)
    await manager.refreshServerModels()
    manager.settings.assignments["a"] = both
    _ = try await manager.respond(to: "write")
    try await Task.sleep(for: .milliseconds(250))
    await manager.prepareForRun()
    #expect(await server.unloads == 0)
  }

  @Test func switchingBackendUnloadsTheOldService() async throws {
    let server = FakeServerService()
    let mlx = FakeLanguageModelService()
    await server.offer(["a"])
    let root = try helper.folder()
    let manager = try make(mlx: mlx, server: server, root: root, backend: .folder)
    manager.settings.assignments["text-model"] = both
    _ = try await manager.respond(to: "write")
    #expect(await mlx.loads == ["text-model"])
    manager.settings.backend = .lmStudio
    await manager.refreshServerModels()
    manager.settings.assignments["a"] = both
    _ = try await manager.respond(to: "write")
    #expect(await mlx.unloads == 1)
    #expect(await server.loads == ["a"])
  }

  @Test func aServerThatIsOffGivesTheClearError() async throws {
    let server = FakeServerService()
    await server.fail(with: .loadFailed("LM Studio does not answer"))
    let manager = try make(server: server)
    manager.settings.assignments["text-model"] = both
    await manager.refreshServerModels()
    #expect(manager.serverError == .loadFailed("LM Studio does not answer"))
    await #expect(throws: LanguageModelError.loadFailed("LM Studio does not answer")) {
      try await manager.respond(to: "write")
    }
    #expect(manager.settings.assignments["text-model"] == both)
  }

  @Test func theImageModelIsStillReleasedBeforeAServerModelLoads() async throws {
    let server = FakeServerService()
    await server.offer(["a"])
    let released = ReleaseCount()
    let manager = try make(server: server, freeImage: true, release: { released.count += 1 })
    await manager.refreshServerModels()
    manager.settings.assignments["a"] = both
    _ = try await manager.respond(to: "write")
    #expect(released.count == 1)
  }

  @Test func theProfileOfAServerModelIsEmpty() {
    let model = ServerModelList.descriptor(id: "a", vision: false)
    let profile = LanguageModelProfile.load(folder: URL(fileURLWithPath: model.path, isDirectory: true))
    #expect(profile.pup == nil)
    #expect(profile.systemPrompt(for: .enhance, withImages: false) == nil)
    #expect(profile.systemPrompt(for: .describe, withImages: true) == nil)
  }

  @Test func anInvalidAddressEmptiesTheListWithAnError() async throws {
    let server = FakeServerService()
    await server.offer(["a"])
    let manager = try make(server: server, serverURL: "http://example.com:1/v1")
    await manager.refreshServerModels()
    #expect(manager.availableModels().isEmpty)
    #expect(manager.serverError != nil)
    #expect(await server.configured.isEmpty)
  }
}
