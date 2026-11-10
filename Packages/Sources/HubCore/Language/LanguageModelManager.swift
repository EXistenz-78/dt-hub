import Foundation
import HubKit
import Observation

/// The one language model of DT Hub (spec §9): loads it when something needs it, frees it when
/// RUN is pressed or after a while without use, and checks the memory first. Everything that
/// asks the model a question goes through `respond`.
@MainActor
@Observable
public final class LanguageModelManager {
  public enum State: Equatable, Sendable {
    case unloaded
    case loading(String)
    case ready(String)
    case failed(LanguageModelError)
  }

  public private(set) var state: State = .unloaded
  public var settings: LanguageModelSettings {
    didSet { store.save(settings) }
  }

  /// Memory the model needs beyond its files (the cache of the answer, the working buffers).
  public static let memoryMargin = 1.2

  /// The models LM Studio's server offers now (empty until `refreshServerModels`, and when the server is off).
  public private(set) var serverModels: [LanguageModelDescriptor] = []
  /// Why the list of the server's models is empty, when it is the server's fault.
  public private(set) var serverError: LanguageModelError?

  @ObservationIgnored private let service: any LanguageModelService
  @ObservationIgnored private let serverService: any ServerLanguageModelService
  /// The source of the model in memory, so `unload` frees it in the service that holds it.
  @ObservationIgnored private var loadedBackend: LanguageModelBackend = .folder
  @ObservationIgnored private let store: LanguageModelSettingsStore
  @ObservationIgnored private let memory: MemoryProbe
  @ObservationIgnored private let releaseImageModel: @MainActor () async -> Void
  @ObservationIgnored private let isImageModelBusy: @MainActor () -> Bool
  @ObservationIgnored private let minute: Duration
  @ObservationIgnored private var loaded: LanguageModelDescriptor?
  @ObservationIgnored private var idleTask: Task<Void, Never>?
  /// Bumped by every request, so an idle timer that started before it gives up.
  @ObservationIgnored private var activity = 0
  /// Bumped by every `unload`, so a load that was under way when memory was asked back knows.
  @ObservationIgnored private var epoch = 0
  /// The load that is under way, so `unload` can wait for the model to arrive and free it.
  @ObservationIgnored private var loading: Task<Void, any Error>?

  /// - Parameters:
  ///   - releaseImageModel: stops the image model's server to make room; used before the
  ///     language model loads, when the settings ask for it.
  ///   - isImageModelBusy: true while an image is being made (or about to be): the image
  ///     model is not released then, whatever the settings say.
  ///   - minute: how long a minute of idle time lasts (shortened in tests).
  public init(
    service: any LanguageModelService, store: LanguageModelSettingsStore = LanguageModelSettingsStore(),
    memory: MemoryProbe = .live, minute: Duration = .seconds(60),
    releaseImageModel: @escaping @MainActor () async -> Void = {},
    isImageModelBusy: @escaping @MainActor () -> Bool = { false },
    serverService: any ServerLanguageModelService = OpenAICompatibleService()
  ) {
    self.service = service
    self.serverService = serverService
    self.store = store
    self.memory = memory
    self.minute = minute
    self.releaseImageModel = releaseImageModel
    self.isImageModelBusy = isImageModelBusy
    settings = store.load()
  }

  public var isLoaded: Bool { loaded != nil }

  /// The models of the chosen source: the folder, or the server's list as of the last `refreshServerModels`.
  public func availableModels() -> [LanguageModelDescriptor] {
    if settings.backend == .lmStudio { return serverModels }
    return LanguageModelScanner.models(in: URL(fileURLWithPath: settings.folder, isDirectory: true))
  }

  /// The folder's models as the last scan found them, without making the caller wait for the disk: the plug-ins' context
  /// goes out at every tab change, on the main thread, and scanning the folder there made each change slower. The first
  /// call scans (nothing to show yet); the later ones answer at once and rescan in the background, and
  /// `onFolderModelsChanged` fires when the rescan finds something different (a model added or removed meanwhile).
  public func availableModelsWithoutWaiting() -> [LanguageModelDescriptor] {
    if settings.backend == .lmStudio { return serverModels }
    let folder = settings.folder
    guard let known = folderScan, known.folder == folder else {
      let models = LanguageModelScanner.models(in: URL(fileURLWithPath: folder, isDirectory: true))
      folderScan = (folder, models)
      return models
    }
    if rescan == nil {
      rescan = Task { [weak self] in
        let fresh = await Task.detached(priority: .utility) {
          LanguageModelScanner.models(in: URL(fileURLWithPath: folder, isDirectory: true))
        }.value
        guard let self else { return }
        self.rescan = nil
        guard self.settings.folder == folder, self.folderScan?.models != fresh else { return }
        self.folderScan = (folder, fresh)
        self.onFolderModelsChanged?()
      }
    }
    return known.models
  }

  /// Called when a background rescan of the models folder found a change.
  @ObservationIgnored public var onFolderModelsChanged: (@MainActor () -> Void)?
  @ObservationIgnored private var folderScan: (folder: String, models: [LanguageModelDescriptor])?
  @ObservationIgnored private var rescan: Task<Void, Never>?

  /// Asks LM Studio for its models (does nothing with the folder as source). A server that is off, or an address
  /// that is not this Mac, empties the list and sets `serverError`.
  public func refreshServerModels() async {
    guard settings.backend == .lmStudio else { return }
    guard let address = LMStudioAddress.validated(settings.serverURL) else {
      serverModels = []
      serverError = .loadFailed("The server address must be http on this Mac, with a port (for example \(LMStudioAddress.defaultURL)).")
      return
    }
    await serverService.configure(address: address, visionModels: settings.serverVisionModels)
    do {
      serverModels = try await serverService.models()
      serverError = nil
    } catch {
      serverModels = []
      serverError = (error as? LanguageModelError) ?? .loadFailed(error.localizedDescription)
    }
  }

  /// The service of the source in use.
  private var activeService: any LanguageModelService {
    settings.backend == .lmStudio ? serverService : service
  }

  /// The service that holds the model in memory.
  private var loadedService: any LanguageModelService {
    loadedBackend == .lmStudio ? serverService : service
  }

  /// The model chosen in the settings, when it still is in the folder.
  public func selectedModel() -> LanguageModelDescriptor? {
    availableModels().first { $0.path == settings.selectedModel }
  }

  /// Asks the model: loads it first when needed (after the memory check), then frees it after
  /// the idle time. `modelNamed` asks a model of the folder by name instead of the one chosen in
  /// the settings (a plug-in's wish): the choice in the settings stays as it is.
  public func respond(
    to prompt: String, images: [URL] = [], options: LanguageModelOptions = LanguageModelOptions(),
    modelNamed name: String? = nil, history: [LanguageModelTurn] = []
  ) async throws(LanguageModelError) -> String {
    activity += 1
    idleTask?.cancel()
    let model: LanguageModelDescriptor
    if let name {
      guard let named = availableModels().first(where: { $0.name == name }) else {
        scheduleIdleUnload()
        throw .modelNotFound(name)
      }
      model = named
    } else {
      // No name: the assignments of Settings › LLM decide (no family known here).
      reconcileAssignments()
      switch self.model(for: images.isEmpty ? .enhance : .describe, family: nil) {
      case .success(let chosen): model = chosen
      case .failure(let error):
        if error == .noModelSelected { state = .failed(error) }
        scheduleIdleUnload()  // a model a plug-in asked for by name may still be loaded
        throw error
      }
    }
    return try await ask(model, prompt, images, options, history)
  }

  /// Asks a model already chosen (by `model(for:family:)`): the prompt buttons' way in.
  public func respond(
    to prompt: String, images: [URL] = [], options: LanguageModelOptions = LanguageModelOptions(),
    model: LanguageModelDescriptor, history: [LanguageModelTurn] = []
  ) async throws(LanguageModelError) -> String {
    activity += 1
    idleTask?.cancel()
    return try await ask(model, prompt, images, options, history)
  }

  /// Settings that change `assignments` when the list of installed LLMs does (see `LanguageModelAssignments`);
  /// saved only if something changed. `downloaded` is the name of a model just downloaded.
  public func reconcileAssignments(downloaded: String? = nil) {
    let models = availableModels()
    var updated = settings
    updated.assignments = LanguageModelAssignments.reconciled(settings, models: models, downloaded: downloaded)
    // The old single choice is consumed once it has become an assignment (not while its disk is away).
    if models.contains(where: { $0.path == settings.selectedModel }) { updated.selectedModel = "" }
    if updated != settings { settings = updated }
  }

  /// The LLM for a prompt button on `family` (nil = unknown), from the assignments.
  public func model(
    for task: LanguageModelTask, family: String?, needs: LanguageModelNeeds = LanguageModelNeeds()
  ) -> Result<LanguageModelDescriptor, LanguageModelError> {
    reconcileAssignments()
    // A server that is off is the reason there is no model: say so, not "no model chosen".
    if settings.backend == .lmStudio, serverModels.isEmpty, let serverError { return .failure(serverError) }
    return LanguageModelRouter.model(
      for: task, family: family, models: availableModels(), assignments: settings.assignments, needs: needs)
  }

  private func ask(
    _ model: LanguageModelDescriptor, _ prompt: String, _ images: [URL], _ options: LanguageModelOptions,
    _ history: [LanguageModelTurn]
  ) async throws(LanguageModelError) -> String {
    if !images.isEmpty, !model.supportsImages {
      scheduleIdleUnload()
      throw .imagesNotSupported
    }
    try await ensureLoaded(model)
    do {
      let answer = try await loadedService.respond(to: prompt, images: images, options: options, history: history)
      scheduleIdleUnload()
      return answer
    } catch let error as LanguageModelError {
      scheduleIdleUnload()
      throw error
    } catch {
      scheduleIdleUnload()
      throw .generationFailed(error.localizedDescription)
    }
  }

  /// Frees the model from memory now.
  public func unload() async {
    epoch += 1
    idleTask?.cancel()
    // A model that is still loading is freed as soon as it has arrived.
    if let loading {
      _ = try? await loading.value
      await loadedService.unload()
      if loaded == nil { state = .unloaded }
    }
    guard loaded != nil else {
      if case .failed = state { state = .unloaded }
      return
    }
    loaded = nil
    state = .unloaded
    await loadedService.unload()
  }

  /// Called when RUN is pressed: frees the model when the settings say so. Nothing to free with LM Studio's
  /// server: its memory is not DT Hub's.
  public func prepareForRun() async {
    guard settings.freeAtRun, settings.backend == .folder else { return }
    await unload()
  }

  // MARK: Loading

  private func ensureLoaded(_ model: LanguageModelDescriptor) async throws(LanguageModelError) {
    if let loaded, loaded.path == model.path { return }
    if loaded != nil { await unload() }
    let ticket = epoch
    // Room first: the image model's server is stopped when the settings ask for it (never
    // while an image is being made), then the free memory is measured, so what it gave back
    // counts.
    if settings.freeImageModelForLanguageModel, !isImageModelBusy() { await releaseImageModel() }
    // RUN was pressed meanwhile: the memory is wanted for the image.
    guard epoch == ticket else { throw .interrupted }
    let needed = Int64(Double(model.sizeBytes) * Self.memoryMargin)
    let available = memory.availableBytes()
    guard needed <= available else {
      let error = LanguageModelError.notEnoughMemory(neededBytes: needed, availableBytes: available)
      state = .failed(error)
      throw error
    }
    state = .loading(model.name)
    loadedBackend = settings.backend
    let service = activeService
    let load = Task { try await service.load(model) }
    loading = load
    defer { if epoch == ticket { loading = nil } }
    do {
      try await load.value
      // RUN was pressed while the model loaded: `unload` frees it, nobody uses it.
      guard epoch == ticket else { throw LanguageModelError.interrupted }
      loaded = model
      state = .ready(model.name)
    } catch let error as LanguageModelError {
      if error != .interrupted { state = .failed(error) }
      throw error
    } catch {
      if epoch != ticket { throw LanguageModelError.interrupted }
      let failure = LanguageModelError.loadFailed(error.localizedDescription)
      state = .failed(failure)
      throw failure
    }
  }

  // MARK: Idle

  private func scheduleIdleUnload() {
    idleTask?.cancel()
    guard settings.idleMinutes > 0, loaded != nil, loadedBackend == .folder else { return }
    let mark = activity
    let wait = minute * settings.idleMinutes
    idleTask = Task { [weak self] in
      try? await Task.sleep(for: wait)
      guard !Task.isCancelled, let self, self.activity == mark else { return }
      await self.unload()
    }
  }
}
