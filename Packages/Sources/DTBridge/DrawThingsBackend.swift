import DrawThingsClient
import Foundation
import HubKit

/// `GenerationBackend` over the Draw Things gRPC server, through DrawThings-Swift.
public actor DrawThingsBackend: GenerationBackend {
  private let endpoint: ServerEndpoint
  private let options: ConnectionOptions
  /// Called each time a gRPC client is created; lets tests count them.
  private let onNewClient: @Sendable () -> Void
  /// Created on demand and dropped after a failed check: a client that could not connect
  /// retries on its own with a backoff that grows to 2 minutes, failing every call meanwhile,
  /// so a fresh one per check keeps reconnection within one check interval (spec §10).
  private var service: DrawThingsService?
  /// The models Draw Things published after the snapshot this app carries; nil in the tests.
  private let communityModels: LiveModelList?
  /// The Official list (the models of the Draw Things app) and the Uncurated one: with DT+ the cloud runs them too.
  private let officialModels: LiveModelList?
  /// The files the server has (from the last echo): their specification is the server's, not one of the lists'.
  private var installedFiles: Set<String> = []
  /// DT+ is on: the models of Draw Things' lists that are not on the server are listed too, for the cloud.
  private let includeRemoteModels: Bool
  private let uncuratedModels: LiveModelList?
  /// What the cloud has: with DT+ the menu lists only its models, and its LoRAs join the local ones.
  private let cloud: CloudCatalog?
  /// Where the specifications of the models the user imported are read from: the server DT Hub starts does not send
  /// them.
  private let customModels: CustomModelSource?

  /// - Parameters:
  ///   - useTLS: the Draw Things API server uses TLS by default (spec §5).
  ///   - sharedSecret: sent with every request when the server requires one.
  ///   - customModels: where to read the specifications of imported models from, for a server that does not send them
  ///     (the one DT Hub starts).
  public init(
    host: String, port: Int, useTLS: Bool, sharedSecret: String?, includeRemoteModels: Bool = false,
    customModels: CustomModelSource? = nil
  ) {
    self.init(
      host: host, port: port, useTLS: useTLS, sharedSecret: sharedSecret, communityModels: .community,
      includeRemoteModels: includeRemoteModels, uncuratedModels: .uncurated, officialModels: .official, cloud: .shared,
      customModels: customModels) {}
  }

  /// The ceiling of a request or reply: 1 GiB. The default (256 MiB) stops an image-to-image or an
  /// inpaint at about 6600 pixels a side (the image is sent as an uncompressed 16-bit tensor).
  static let maxMessageBytes = 1024 * 1024 * 1024

  init(
    host: String, port: Int, useTLS: Bool, sharedSecret: String?, communityModels: LiveModelList? = nil,
    includeRemoteModels: Bool = false, uncuratedModels: LiveModelList? = nil, officialModels: LiveModelList? = nil,
    cloud: CloudCatalog? = nil, customModels: CustomModelSource? = nil,
    onNewClient: @escaping @Sendable () -> Void
  ) {
    self.communityModels = communityModels
    self.includeRemoteModels = includeRemoteModels
    self.uncuratedModels = uncuratedModels
    self.officialModels = officialModels
    self.cloud = cloud
    self.customModels = customModels
    endpoint = ServerEndpoint(host: host, port: port)
    options = ConnectionOptions(
      security: useTLS ? .tls() : .plaintext,
      sharedSecret: sharedSecret,
      maxMessageBytes: Self.maxMessageBytes,
      // The echo doubles as the connection check: fail fast instead of the 30 s default.
      requestTimeout: .seconds(5),
      // The package's own remote list is left off: it would be re-fetched for every unknown file while offline.
      // Official models newer than the bundled snapshot come from `LiveModelList`, downloaded once and kept on disk.
      modelSpecs: .bundled)
    self.onNewClient = onNewClient
  }

  public func fetchCatalog() async throws -> ModelCatalog {
    let service = currentService()
    let reply: EchoReply
    do {
      reply = try await service.echo(name: "DT Hub")
    } catch {
      discard(service)
      if case DrawThingsError.unauthenticated = error { throw BackendError.unauthorized }
      throw BackendError.unreachable(error.localizedDescription)
    }
    // The models released after the bundled snapshot: registered, they are listed and their requests carry the
    // right specification.
    installedFiles = Set(reply.files)
    let live: [String: Data] = await communityModels?.specs() ?? [:]
    if !live.isEmpty {
      await service.modelSpecs.register(Self.specs(toRegisterFor: reply.files, live: live))
    }
    // The bundled video specs, only for the files nobody (the server, the lists) describes.
    var described: Set<String> = []
    for file in reply.files where VideoModelSpecs.byFile[file] != nil {
      if await service.modelSpecs.spec(for: file) != nil { described.insert(file) }
    }
    let bundled = Self.bundledSpecs(toRegisterFor: reply.files, described: described)
    if !bundled.isEmpty { await service.modelSpecs.register(bundled) }
    // The imported models the server did not describe: their specification is in a custom.json.
    if let customModels {
      var described: Set<String> = []
      for file in reply.files where await service.modelSpecs.spec(for: file) != nil { described.insert(file) }
      let custom = CustomModelFiles.specs(for: reply.files, described: described, source: customModels)
      let undescribed = custom.values.compactMap { ModelSpec(json: $0) }
      if !undescribed.isEmpty { await service.modelSpecs.register(undescribed) }
    }
    var specs: [String: ModelSpecInfo] = [:]
    for file in reply.files {
      if let spec = await service.modelSpecs.spec(for: file) {
        specs[file] = CatalogBuilder.specInfo(json: spec.json, file: file)
      }
    }
    let catalog = CatalogBuilder.build(files: reply.files, modelSpecs: specs, loraMetadata: reply.override.loras)
    guard includeRemoteModels else { return catalog }
    // Official first, then Community (`live`), then Uncurated: a file in two lists keeps the description of the first.
    let official: [String: Data] = await officialModels?.specs() ?? [:]
    let uncurated: [String: Data] = await uncuratedModels?.specs() ?? [:]
    let remote = VideoModelSpecs.filling(
      uncurated.merging(live) { _, community in community }.merging(official) { _, official in official })
    let sources = CatalogBuilder.sources(
      official: official, community: live, uncurated: uncurated, bundled: Set(VideoModelSpecs.byFile.keys))
    // The cloud's own list: only what it can run. Without it (never reached, nothing saved) every model of the lists.
    if let cloudFiles = await cloud?.files() {
      let cloudLoRAs = await cloud?.loras() ?? []
      return CatalogBuilder.cloudCatalog(
        local: catalog, specs: remote, sources: sources, deprecated: await officialModels?.deprecated() ?? [],
        cloudFiles: cloudFiles, cloudLoRAs: cloudLoRAs)
    }
    return CatalogBuilder.addingRemoteModels(to: catalog, live: remote, sources: sources)
  }

  /// A model the server's folder does not have (DT+): its specification goes with the request, so the cloud knows it.
  private func registerRemoteSpec(for file: String, loras lorasFiles: [String], on service: DrawThingsService) async {
    guard includeRemoteModels else { return }
    // A model the server has is described by the server (its echo): the lists' specifications, thinner for the
    // Official ones, must not replace it.
    var json: Data?
    if Self.shouldRegisterRemoteSpec(for: file, installed: installedFiles) {
      json = (await officialModels?.specs() ?? [:])[file]
      if json == nil { json = (await communityModels?.specs() ?? [:])[file] }
      if json == nil { json = (await uncuratedModels?.specs() ?? [:])[file] }
    }
    // A video model that neither the server nor the service describes (installed or not) gets the bundled spec.
    if json == nil, let bundled = VideoModelSpecs.data(for: file), await service.modelSpecs.spec(for: file) == nil {
      json = bundled
    }
    var specs = [json.flatMap { ModelSpec(json: $0) }].compactMap { $0 }
    // The cloud's LoRAs with their official description (otherwise the override would carry a minimal one).
    if !lorasFiles.isEmpty, let cloudLoRAs = await cloud?.loraSpecs() {
      specs += lorasFiles.compactMap { cloudLoRAs[$0].flatMap { ModelSpec(json: $0) } }
    }
    if !specs.isEmpty { await service.modelSpecs.register(specs) }
  }

  /// Only a model the server does not have (it runs in the cloud) carries its specification from a list.
  static func shouldRegisterRemoteSpec(for file: String, installed: Set<String>) -> Bool { !installed.contains(file) }

  /// The specifications of the live list for the files the server has.
  static func specs(toRegisterFor files: [String], live: [String: Data]) -> [ModelSpec] {
    files.compactMap { live[$0] }.compactMap { ModelSpec(json: $0) }
  }

  /// The bundled specs of the video files that nothing describes yet (`described`: the files the service already has a
  /// spec for); a spec of the server or of a list is never replaced.
  static func bundledSpecs(toRegisterFor files: [String], described: Set<String>) -> [ModelSpec] {
    files.filter { !described.contains($0) }.compactMap { VideoModelSpecs.data(for: $0) }.compactMap { ModelSpec(json: $0) }
  }

  public nonisolated func generate(_ job: GenerationJob, inputs: GenerationInputs) -> AsyncThrowingStream<GenerationUpdate, any Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let service = await self.currentService()
          await self.registerRemoteSpec(for: job.model, loras: job.parameters.loras.map(\.file), on: service)
          // The actor's state, read before the events come in.
          let runsLocally = await self.runsLocally(job.model)
          let hires = job.parameters.advanced.hiresFix ? job.parameters.advanced.hiresFixStrength : nil
          for try await event in service.stream(try JobMapper.request(for: job, inputs: inputs)) {
            if let update = try JobMapper.update(
              for: event, expected: job.parameters.batchSize, videoFPS: job.videoFPS, runsLocally: runsLocally,
              requestedFrames: job.parameters.video.numFrames, hiresFixStrength: hires)
            {
              continuation.yield(update)
            }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: JobMapper.backendError(for: error))
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// The model's files are on the server (otherwise the cloud runs it).
  private func runsLocally(_ model: String) -> Bool { installedFiles.contains(model) }

  public func shutdown() async {
    await service?.shutdown()
    service = nil
  }

  private func currentService() -> DrawThingsService {
    if let service { return service }
    let created = DrawThingsService(endpoint: endpoint, options: options)
    service = created
    onNewClient()
    return created
  }

  /// Forgets a failed client; its shutdown runs on its own so the check is not held up.
  private func discard(_ failed: DrawThingsService) {
    if service === failed { service = nil }
    Task { await failed.shutdown() }
  }
}
