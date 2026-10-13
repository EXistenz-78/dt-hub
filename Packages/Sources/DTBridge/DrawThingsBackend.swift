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
  private let liveModels: LiveModelList?

  /// - Parameters:
  ///   - useTLS: the Draw Things API server uses TLS by default (spec §5).
  ///   - sharedSecret: sent with every request when the server requires one.
  public init(host: String, port: Int, useTLS: Bool, sharedSecret: String?) {
    self.init(host: host, port: port, useTLS: useTLS, sharedSecret: sharedSecret, liveModels: .shared) {}
  }

  /// The ceiling of a request or reply: 1 GiB. The default (256 MiB) stops an image-to-image or an
  /// inpaint at about 6600 pixels a side (the image is sent as an uncompressed 16-bit tensor).
  static let maxMessageBytes = 1024 * 1024 * 1024

  init(
    host: String, port: Int, useTLS: Bool, sharedSecret: String?, liveModels: LiveModelList? = nil,
    onNewClient: @escaping @Sendable () -> Void
  ) {
    self.liveModels = liveModels
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
    if let live = await liveModels?.specs(), !live.isEmpty {
      await service.modelSpecs.register(Self.specs(toRegisterFor: reply.files, live: live))
    }
    var specs: [String: ModelSpecInfo] = [:]
    for file in reply.files {
      if let spec = await service.modelSpecs.spec(for: file) {
        specs[file] = CatalogBuilder.specInfo(json: spec.json, file: file)
      }
    }
    return CatalogBuilder.build(files: reply.files, modelSpecs: specs, loraMetadata: reply.override.loras)
  }

  /// The specifications of the live list for the files the server has.
  static func specs(toRegisterFor files: [String], live: [String: Data]) -> [ModelSpec] {
    files.compactMap { live[$0] }.compactMap { ModelSpec(json: $0) }
  }

  public nonisolated func generate(_ job: GenerationJob, inputs: GenerationInputs) -> AsyncThrowingStream<GenerationUpdate, any Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let service = await self.currentService()
          for try await event in service.stream(try JobMapper.request(for: job, inputs: inputs)) {
            if let update = try JobMapper.update(for: event) { continuation.yield(update) }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: JobMapper.backendError(for: error))
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

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
