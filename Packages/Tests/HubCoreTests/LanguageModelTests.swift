import Foundation
import HubKit
import Testing

@testable import HubCore

struct LanguageModelScannerTests {
  func makeRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("LanguageModelScannerTests-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  /// A model folder: a config, weights of `size` bytes, optionally a vision section.
  func model(_ path: String, in root: URL, size: Int = 100, vision: Bool = false, weights: Bool = true) throws {
    let folder = root.appendingPathComponent(path, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try (vision ? #"{"vision_config": {}}"# : #"{"model_type": "qwen3"}"#).write(
      to: folder.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
    if weights { try Data(count: size).write(to: folder.appendingPathComponent("model.safetensors")) }
  }

  @Test func findsModelsOneAndTwoLevelsDeep() throws {
    let root = try makeRoot()
    try model("Qwen3-4B-4bit", in: root)
    try model("mlx-community/Qwen3-VL-8B-Instruct-4bit", in: root, size: 5000, vision: true)
    let found = LanguageModelScanner.models(in: root)
    #expect(found.map(\.name) == ["mlx-community/Qwen3-VL-8B-Instruct-4bit", "Qwen3-4B-4bit"])
    #expect(found[0].supportsImages && !found[1].supportsImages)
    #expect(found[0].sizeBytes >= 5000)
    #expect(found[1].path == root.appendingPathComponent("Qwen3-4B-4bit").standardizedFileURL.path)
  }

  @Test func aFolderWithoutWeightsOrConfigIsNotAModel() throws {
    let root = try makeRoot()
    try model("no-weights", in: root, weights: false)
    let loose = root.appendingPathComponent("only-weights")
    try FileManager.default.createDirectory(at: loose, withIntermediateDirectories: true)
    try Data(count: 10).write(to: loose.appendingPathComponent("model.safetensors"))
    #expect(LanguageModelScanner.models(in: root).isEmpty)
  }

  @Test func doesNotLookDeeperThanTwoLevelsOrInsideAModel() throws {
    let root = try makeRoot()
    try model("a/b/c/too-deep", in: root)
    try model("outer", in: root)
    try model("outer/inner", in: root)
    #expect(LanguageModelScanner.models(in: root).map(\.name) == ["outer"])
  }

  @Test func aMissingFolderHasNoModels() {
    #expect(LanguageModelScanner.models(in: URL(fileURLWithPath: "/nowhere/\(UUID())")).isEmpty)
  }
}

struct LanguageModelSettingsTests {
  @Test func theMemoryOptionsAreOnlyOnForMacsWithLessThan64GB() {
    let gb: UInt64 = 1_073_741_824
    #expect(LanguageModelSettings.defaults(physicalMemory: 32 * gb).freeAtRun)
    #expect(LanguageModelSettings.defaults(physicalMemory: 32 * gb).freeImageModelForLanguageModel)
    #expect(!LanguageModelSettings.defaults(physicalMemory: 64 * gb).freeAtRun)
    #expect(!LanguageModelSettings.defaults(physicalMemory: 192 * gb).freeImageModelForLanguageModel)
    #expect(LanguageModelSettings.defaults(physicalMemory: 64 * gb).folder == "/Volumes/LLM-VLM/MLX")
    #expect(LanguageModelSettings.defaults(physicalMemory: 64 * gb).idleMinutes == 10)
  }

  @Test func theStoreRemembersAndFallsBackToTheMacsDefaults() {
    let defaults = UserDefaults(suiteName: "LanguageModelSettingsTests-\(UUID())")!
    let store = LanguageModelSettingsStore(defaults: defaults, physicalMemory: 16 * 1_073_741_824)
    #expect(store.load().freeAtRun)
    var settings = store.load()
    settings.freeAtRun = false
    settings.selectedModel = "/m"
    store.save(settings)
    #expect(store.load() == settings)
    defaults.set(Data("garbage".utf8), forKey: LanguageModelSettingsStore.key)
    #expect(store.load().freeAtRun)
  }

  @Test func idleMinutesStayInRangeAndOldFilesLoad() throws {
    #expect(LanguageModelSettings(idleMinutes: 9999).clamped().idleMinutes == 240)
    #expect(LanguageModelSettings(idleMinutes: -3).clamped().idleMinutes == 0)
    let decoded = try JSONDecoder().decode(LanguageModelSettings.self, from: Data(#"{"folder": "/x"}"#.utf8))
    #expect(decoded.folder == "/x")
    #expect(decoded.idleMinutes == 10)
  }

  @Test func theLiveProbeReportsSomeMemory() {
    #expect(MemoryProbe.live.availableBytes() > 0)
  }
}

/// A language model that is never really loaded.
actor FakeLanguageModelService: LanguageModelService {
  private(set) var loads: [String] = []
  private(set) var unloads = 0
  private(set) var questions: [(String, [URL])] = []
  var loadError: LanguageModelError?
  var answer = "an answer"
  private var loadGate: Gate?

  /// Makes every load wait until the gate opens (a model that takes its time to load).
  func holdLoads(until gate: Gate) { loadGate = gate }

  func fail(with error: LanguageModelError?) { loadError = error }

  func load(_ model: LanguageModelDescriptor) async throws {
    if let loadGate { await loadGate.wait() }
    if let loadError { throw loadError }
    loads.append(model.name)
  }

  func unload() async { unloads += 1 }

  func respond(to prompt: String, images: [URL]) async throws -> String {
    questions.append((prompt, images))
    return answer
  }
}

@MainActor
struct LanguageModelManagerTests {
  /// A folder with a 1000-byte text model and a 4000-byte vision model.
  func folder() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("LanguageModelManagerTests-\(UUID())")
    for (name, size, vision) in [("text-model", 1000, false), ("vision-model", 4000, true)] {
      let dir = root.appendingPathComponent(name)
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      try (vision ? #"{"vision_config": {}}"# : "{}").write(to: dir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
      try Data(count: size).write(to: dir.appendingPathComponent("w.safetensors"))
    }
    return root
  }

  func manager(
    _ service: FakeLanguageModelService, root: URL, selected: String = "text-model", available: Int64 = 1_000_000,
    idle: Int = 10, freeAtRun: Bool = false, freeImage: Bool = false, release: @escaping @MainActor () async -> Void = {},
    busy: @escaping @MainActor () -> Bool = { false }
  ) -> LanguageModelManager {
    let defaults = UserDefaults(suiteName: "LanguageModelManagerTests-\(UUID())")!
    let store = LanguageModelSettingsStore(defaults: defaults, physicalMemory: 64 * 1_073_741_824)
    let manager = LanguageModelManager(
      service: service, store: store, memory: MemoryProbe { available }, minute: .milliseconds(40), releaseImageModel: release,
      isImageModelBusy: busy)
    manager.settings = LanguageModelSettings(
      folder: root.path, selectedModel: root.appendingPathComponent(selected).standardizedFileURL.path,
      freeAtRun: freeAtRun, freeImageModelForLanguageModel: freeImage, idleMinutes: idle)
    return manager
  }

  @Test func loadsTheChosenModelOnTheFirstQuestionOnly() async throws {
    let service = FakeLanguageModelService()
    let manager = manager(service, root: try folder())
    #expect(try await manager.respond(to: "hello") == "an answer")
    #expect(try await manager.respond(to: "again") == "an answer")
    #expect(await service.loads == ["text-model"])
    #expect(manager.state == .ready("text-model"))
  }

  @Test func withoutAChosenModelItSaysSo() async throws {
    let manager = manager(FakeLanguageModelService(), root: try folder(), selected: "missing")
    await #expect(throws: LanguageModelError.noModelSelected) { try await manager.respond(to: "hi") }
    #expect(manager.state == .failed(.noModelSelected))
  }

  @Test func imagesNeedAVisionModel() async throws {
    let service = FakeLanguageModelService()
    let root = try folder()
    let text = manager(service, root: root)
    await #expect(throws: LanguageModelError.imagesNotSupported) {
      try await text.respond(to: "what is this?", images: [URL(fileURLWithPath: "/tmp/a.png")])
    }
    let vision = manager(service, root: root, selected: "vision-model")
    _ = try await vision.respond(to: "what is this?", images: [URL(fileURLWithPath: "/tmp/a.png")])
    #expect(await service.questions.last?.1 == [URL(fileURLWithPath: "/tmp/a.png")])
  }

  @Test func refusesToLoadWhatDoesNotFitInTheFreeMemory() async throws {
    let service = FakeLanguageModelService()
    let manager = manager(service, root: try folder(), selected: "vision-model", available: 4000)
    // The model's files plus 20 % do not fit in 4000 bytes.
    let size = try #require(manager.selectedModel()).sizeBytes
    let needed = Int64(Double(size) * LanguageModelManager.memoryMargin)
    #expect(needed > 4000)
    await #expect(throws: LanguageModelError.notEnoughMemory(neededBytes: needed, availableBytes: 4000)) {
      try await manager.respond(to: "hi")
    }
    #expect(await service.loads.isEmpty)
    #expect(manager.state == .failed(.notEnoughMemory(neededBytes: needed, availableBytes: 4000)))
  }

  @Test func aLoadFailureIsReported() async throws {
    let service = FakeLanguageModelService()
    await service.fail(with: .loadFailed("bad weights"))
    let manager = manager(service, root: try folder())
    await #expect(throws: LanguageModelError.loadFailed("bad weights")) { try await manager.respond(to: "hi") }
    #expect(!manager.isLoaded)
  }

  @Test func switchingModelsFreesTheOldOneFirst() async throws {
    let service = FakeLanguageModelService()
    let root = try folder()
    let manager = manager(service, root: root)
    _ = try await manager.respond(to: "one")
    manager.settings.selectedModel = root.appendingPathComponent("vision-model").standardizedFileURL.path
    _ = try await manager.respond(to: "two")
    #expect(await service.loads == ["text-model", "vision-model"])
    #expect(await service.unloads == 1)
  }

  @Test func pressingRunFreesTheModelOnlyWhenTheSettingsSaySo() async throws {
    let service = FakeLanguageModelService()
    let root = try folder()
    let keep = manager(service, root: root, freeAtRun: false)
    _ = try await keep.respond(to: "hi")
    await keep.prepareForRun()
    #expect(keep.isLoaded)
    let free = manager(service, root: root, freeAtRun: true)
    _ = try await free.respond(to: "hi")
    await free.prepareForRun()
    #expect(!free.isLoaded)
    #expect(free.state == .unloaded)
    #expect(await service.unloads == 1)
  }

  @Test func freesTheModelAfterTheIdleTime() async throws {
    let service = FakeLanguageModelService()
    let manager = manager(service, root: try folder(), idle: 2)
    _ = try await manager.respond(to: "hi")
    #expect(manager.isLoaded)
    for _ in 0..<60 where manager.isLoaded { try await Task.sleep(for: .milliseconds(50)) }
    #expect(!manager.isLoaded)
    #expect(await service.unloads == 1)
  }

  @Test func useRestartsTheIdleTime() async throws {
    let service = FakeLanguageModelService()
    let manager = manager(service, root: try folder(), idle: 5)
    _ = try await manager.respond(to: "one")
    try await Task.sleep(for: .milliseconds(100))
    _ = try await manager.respond(to: "two")
    try await Task.sleep(for: .milliseconds(120))
    // 5 × 40 ms = 200 ms since the second question: still loaded after 120 ms.
    #expect(manager.isLoaded)
    #expect(await service.loads.count == 1)
  }

  @Test func idleMinutesAtZeroNeverFreesTheModel() async throws {
    let service = FakeLanguageModelService()
    let manager = manager(service, root: try folder(), idle: 0)
    _ = try await manager.respond(to: "hi")
    try await Task.sleep(for: .milliseconds(150))
    #expect(manager.isLoaded)
  }

  @Test func theImageModelIsReleasedOnlyBeforeALoadAndOnlyWhenAsked() async throws {
    let service = FakeLanguageModelService()
    let root = try folder()
    let released = Counter()
    let on = manager(service, root: root, freeImage: true, release: { released.add() })
    _ = try await on.respond(to: "one")
    _ = try await on.respond(to: "two")
    #expect(released.count == 1)  // not again while the model stays loaded
    let off = manager(service, root: root, freeImage: false, release: { released.add() })
    _ = try await off.respond(to: "one")
    #expect(released.count == 1)
  }

  @Test func theImageModelIsLeftAloneWhileAnImageIsBeingGenerated() async throws {
    let service = FakeLanguageModelService()
    let released = Counter()
    let manager = manager(service, root: try folder(), freeImage: true, release: { released.add() }, busy: { true })
    _ = try await manager.respond(to: "hi")
    #expect(released.count == 0)
    #expect(manager.isLoaded)
  }

  /// Waits (up to 5 s) for the manager to show `state`.
  func waitFor(_ state: LanguageModelManager.State, in manager: LanguageModelManager) async throws {
    for _ in 0..<100 where manager.state != state { try await Task.sleep(for: .milliseconds(50)) }
    #expect(manager.state == state)
  }

  @Test func pressingRunWhileTheModelLoadsFreesItWhenItArrives() async throws {
    let service = FakeLanguageModelService()
    let gate = Gate()
    await service.holdLoads(until: gate)
    let manager = manager(service, root: try folder(), freeAtRun: true)
    let asking = Task { () -> LanguageModelError? in
      do throws(LanguageModelError) { _ = try await manager.respond(to: "hi") } catch { return error }
      return nil
    }
    try await waitFor(.loading("text-model"), in: manager)
    let running = Task { await manager.prepareForRun() }
    try await Task.sleep(for: .milliseconds(100))
    await gate.open()
    await running.value
    #expect(await asking.value == .interrupted)
    #expect(!manager.isLoaded)
    #expect(manager.state == .unloaded)
    #expect(await service.unloads >= 1)
  }

  @Test func pressingRunWhileTheImageModelLeavesStopsTheLoad() async throws {
    let service = FakeLanguageModelService()
    let gate = Gate()
    let manager = manager(service, root: try folder(), freeAtRun: true, freeImage: true, release: { await gate.wait() })
    let asking = Task { () -> LanguageModelError? in
      do throws(LanguageModelError) { _ = try await manager.respond(to: "hi") } catch { return error }
      return nil
    }
    try await Task.sleep(for: .milliseconds(100))
    await manager.prepareForRun()
    await gate.open()
    #expect(await asking.value == .interrupted)
    #expect(await service.loads.isEmpty)
    #expect(!manager.isLoaded)
  }

  @Test func theMemoryIsMeasuredAfterTheImageModelLeft() async throws {
    let service = FakeLanguageModelService()
    let probe = MutableMemory(1000)
    let defaults = UserDefaults(suiteName: "LanguageModelManagerTests-\(UUID())")!
    let root = try folder()
    let manager = LanguageModelManager(
      service: service, store: LanguageModelSettingsStore(defaults: defaults), memory: MemoryProbe { probe.value },
      minute: .milliseconds(40), releaseImageModel: { probe.value = 1_000_000 })
    manager.settings = LanguageModelSettings(
      folder: root.path, selectedModel: root.appendingPathComponent("vision-model").standardizedFileURL.path,
      freeAtRun: false, freeImageModelForLanguageModel: true, idleMinutes: 10)
    _ = try await manager.respond(to: "needs the room")
    #expect(manager.isLoaded)
  }
}

/// Holds callers until it is opened.
actor Gate {
  private var isOpen = false
  private var waiting: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    if isOpen { return }
    await withCheckedContinuation { waiting.append($0) }
  }

  func open() {
    isOpen = true
    waiting.forEach { $0.resume() }
    waiting = []
  }
}

final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0
  func add() { lock.withLock { value += 1 } }
  var count: Int { lock.withLock { value } }
}

final class MutableMemory: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: Int64
  init(_ value: Int64) { stored = value }
  var value: Int64 {
    get { lock.withLock { stored } }
    set { lock.withLock { stored = newValue } }
  }
}
