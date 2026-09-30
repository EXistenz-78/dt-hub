import DrawThingsClient
import HubKit

/// `GenerationBackend` over the Draw Things gRPC server, through DrawThings-Swift.
public final class DrawThingsBackend: GenerationBackend {
  private let service: DrawThingsService

  /// - Parameters:
  ///   - useTLS: the Draw Things API server uses TLS by default (spec §5).
  ///   - sharedSecret: sent with every request when the server requires one.
  public init(host: String, port: Int, useTLS: Bool, sharedSecret: String?) {
    let options = ConnectionOptions(
      security: useTLS ? .tls() : .plaintext,
      sharedSecret: sharedSecret,
      // The echo doubles as the connection check: fail fast instead of the 30 s default.
      requestTimeout: .seconds(5),
      // Bundled specs only: the remote list would be re-fetched for every unknown file
      // while offline. Official models newer than the bundled snapshot need a package update.
      modelSpecs: .bundled)
    service = DrawThingsService(endpoint: ServerEndpoint(host: host, port: port), options: options)
  }

  public func fetchCatalog() async throws -> ModelCatalog {
    let reply: EchoReply
    do {
      reply = try await service.echo(name: "DT Hub")
    } catch DrawThingsError.unauthenticated {
      throw BackendError.unauthorized
    } catch {
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
    await service.shutdown()
  }
}
