import DrawThingsClient
import Foundation
import HubKit

/// What Draw Things' cloud (DT+) offers: the files of its server, from an echo to compute.drawthings.ai (no account
/// needed), and the description of the official LoRAs (`loras.json`, for their family and trigger). Each is fetched
/// once per launch and kept on disk, like the model lists; a failed attempt is retried after 10 minutes.
public actor CloudCatalog {
  public static let server = ServerEndpoint(host: "compute.drawthings.ai", port: 443)
  public static let lorasAddress = URL(string: "https://models.drawthings.ai/loras.json")!

  /// …/DT Hub/dtplus-files.json and …/DT Hub/loras-list.json.
  public static let shared = CloudCatalog(
    filesCache: CachedDownload.supportFile("dtplus-files.json"), lorasCache: CachedDownload.supportFile("loras-list.json"))

  private let fileList: CachedDownload
  private let loraList: CachedDownload
  private var parsedFiles: (generation: Int, files: Set<String>)?

  init(
    filesCache: URL, lorasCache: URL,
    echo: @escaping @Sendable () async throws -> [String] = CloudCatalog.echo,
    download: @escaping @Sendable (URL) async throws -> Data = CachedDownload.fetch
  ) {
    fileList = CachedDownload(
      address: URL(string: "https://\(Self.server.host):\(Self.server.port)")!, cacheURL: filesCache,
      isValid: { !Self.decode($0).isEmpty },
      download: { _ in try JSONEncoder().encode(try await echo()) })
    loraList = CachedDownload(
      address: Self.lorasAddress, cacheURL: lorasCache,
      isValid: { !CatalogBuilder.parseLoRAMetadata($0).isEmpty }, download: download)
  }

  /// The files of the cloud; nil when they were never obtained (no answer and nothing saved).
  public func files() async -> Set<String>? {
    guard let data = await fileList.data() else { return nil }
    let generation = await fileList.generation
    if let parsedFiles, parsedFiles.generation == generation { return parsedFiles.files }
    let files = Self.decode(data)
    parsedFiles = (generation, files)
    return files.isEmpty ? nil : files
  }

  /// The official LoRAs as Draw Things describes them; empty when the list was never downloaded.
  public func loras() async -> [CatalogLoRA] {
    CatalogBuilder.parseLoRAMetadata(await loraList.data() ?? Data())
  }

  /// The same LoRAs as Draw Things' JSON objects, by file: a cloud LoRA's goes into the request's override, so the
  /// cloud reads it with its own name, trigger and family.
  public func loraSpecs() async -> [String: Data] {
    LiveModelList.parse(await loraList.data() ?? Data())
  }

  static func decode(_ data: Data) -> Set<String> {
    Set((try? JSONDecoder().decode([String].self, from: data)) ?? [])
  }

  /// The echo of the cloud's server: its reply lists every file it has.
  public static let echo: @Sendable () async throws -> [String] = {
    let service = DrawThingsService(
      endpoint: server,
      options: ConnectionOptions(security: .tls(), sharedSecret: nil, requestTimeout: .seconds(10), modelSpecs: .bundled))
    defer { Task { await service.shutdown() } }
    return try await service.echo(name: "DT Hub").files
  }
}
