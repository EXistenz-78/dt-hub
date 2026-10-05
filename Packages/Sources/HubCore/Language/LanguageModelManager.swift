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

  @ObservationIgnored private let service: any LanguageModelService
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
    isImageModelBusy: @escaping @MainActor () -> Bool = { false }
  ) {
    self.service = service
    self.store = store
    self.memory = memory
    self.minute = minute
    self.releaseImageModel = releaseImageModel
    self.isImageModelBusy = isImageModelBusy
    settings = store.load()
  }

  public var isLoaded: Bool { loaded != nil }

  /// The models in the chosen folder.
  public func availableModels() -> [LanguageModelDescriptor] {
    LanguageModelScanner.models(in: URL(fileURLWithPath: settings.folder, isDirectory: true))
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
    modelNamed name: String? = nil
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
      guard let chosen = selectedModel() else {
        state = .failed(.noModelSelected)
        scheduleIdleUnload()  // a model a plug-in asked for by name may still be loaded
        throw .noModelSelected
      }
      model = chosen
    }
    if !images.isEmpty, !model.supportsImages {
      scheduleIdleUnload()
      throw .imagesNotSupported
    }
    try await ensureLoaded(model)
    do {
      let answer = try await service.respond(to: prompt, images: images, options: options)
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
      await service.unload()
      if loaded == nil { state = .unloaded }
    }
    guard loaded != nil else {
      if case .failed = state { state = .unloaded }
      return
    }
    loaded = nil
    state = .unloaded
    await service.unload()
  }

  /// Called when RUN is pressed: frees the model when the settings say so.
  public func prepareForRun() async {
    guard settings.freeAtRun else { return }
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
    let service = service
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
    guard settings.idleMinutes > 0, loaded != nil else { return }
    let mark = activity
    let wait = minute * settings.idleMinutes
    idleTask = Task { [weak self] in
      try? await Task.sleep(for: wait)
      guard !Task.isCancelled, let self, self.activity == mark else { return }
      await self.unload()
    }
  }
}
