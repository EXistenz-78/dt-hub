import DrawThingsClient
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

  /// - Parameters:
  ///   - useTLS: the Draw Things API server uses TLS by default (spec §5).
  ///   - sharedSecret: sent with every request when the server requires one.
  public init(host: String, port: Int, useTLS: Bool, sharedSecret: String?) {
    self.init(host: host, port: port, useTLS: useTLS, sharedSecret: sharedSecret) {}
  }

  init(
    host: String, port: Int, useTLS: Bool, sharedSecret: String?,
    onNewClient: @escaping @Sendable () -> Void
  ) {
    endpoint = ServerEndpoint(host: host, port: port)
    options = ConnectionOptions(
      security: useTLS ? .tls() : .plaintext,
      sharedSecret: sharedSecret,
      // The echo doubles as the connection check: fail fast instead of the 30 s default.
      requestTimeout: .seconds(5),
      // Bundled specs only: the remote list would be re-fetched for every unknown file
      // while offline. Official models newer than the bundled snapshot need a package update.
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
    var specs: [String: ModelSpecInfo] = [:]
    for file in reply.files {
      if let spec = await service.modelSpecs.spec(for: file) {
        specs[file] = CatalogBuilder.specInfo(json: spec.json, file: file)
      }
    }
    return CatalogBuilder.build(files: reply.files, modelSpecs: specs, loraMetadata: reply.override.loras)
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
