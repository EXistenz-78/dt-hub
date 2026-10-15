import DrawThingsClient
import Foundation
import HubKit

/// What the cloud's echo carries and DT Hub keeps: the files, and the compute-unit policy while the server announces
/// one (the fields are 0 without it).
struct CloudEcho: Codable, Sendable, Equatable {
  var files: [String]
  var plus: Double = 0
  var community: Double = 0
  /// Unix seconds; 0 when there is no policy.
  var expireAt: Int64 = 0
}

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
  private var parsedEcho: (generation: Int, echo: CloudEcho)?

  init(
    filesCache: URL, lorasCache: URL,
    echo: @escaping @Sendable () async throws -> CloudEcho = CloudCatalog.echo,
    download: @escaping @Sendable (URL) async throws -> Data = CachedDownload.fetch
  ) {
    fileList = CachedDownload(
      address: URL(string: "https://\(Self.server.host):\(Self.server.port)")!, cacheURL: filesCache,
      isValid: { !(Self.decode($0)?.files.isEmpty ?? true) },
      download: { _ in try JSONEncoder().encode(try await echo()) })
    loraList = CachedDownload(
      address: Self.lorasAddress, cacheURL: lorasCache,
      isValid: { !CatalogBuilder.parseLoRAMetadata($0).isEmpty }, download: download)
  }

  /// The files of the cloud; nil when they were never obtained (no answer and nothing saved).
  public func files() async -> Set<String>? {
    guard let echo = await currentEcho() else { return nil }
    let files = Set(echo.files)
    return files.isEmpty ? nil : files
  }

  /// The compute-unit limits: Draw Things' defaults, unless the server announced a policy (Plus above 0) that has
  /// not expired by `now` (spec §2). Without an answer or a saved copy, the defaults.
  public func limits(now: Date = Date()) async -> CULimits {
    guard let echo = await currentEcho(), echo.plus > 0, echo.expireAt > 0 else { return .standard }
    let expiry = Date(timeIntervalSince1970: TimeInterval(echo.expireAt))
    guard now < expiry else { return .standard }
    return CULimits(
      plus: Int(echo.plus), community: echo.community > 0 ? Int(echo.community) : CULimits.standard.community,
      expiresAt: expiry)
  }

  private func currentEcho() async -> CloudEcho? {
    guard let data = await fileList.data() else { return nil }
    let generation = await fileList.generation
    if let parsedEcho, parsedEcho.generation == generation { return parsedEcho.echo }
    guard let echo = Self.decode(data) else { return nil }
    parsedEcho = (generation, echo)
    return echo
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

  /// The saved echo; the first versions of DT Hub saved only the list of files.
  static func decode(_ data: Data) -> CloudEcho? {
    if let echo = try? JSONDecoder().decode(CloudEcho.self, from: data) { return echo }
    if let files = try? JSONDecoder().decode([String].self, from: data) { return CloudEcho(files: files) }
    return nil
  }

  /// The echo of the cloud's server: its reply lists every file it has, and carries `thresholds` only while a
  /// temporary compute-unit policy is active.
  static let echo: @Sendable () async throws -> CloudEcho = {
    let service = DrawThingsService(
      endpoint: server,
      options: ConnectionOptions(security: .tls(), sharedSecret: nil, requestTimeout: .seconds(10), modelSpecs: .bundled))
    defer { Task { await service.shutdown() } }
    let reply = try await service.echo(name: "DT Hub")
    guard reply.hasThresholds else { return CloudEcho(files: reply.files) }
    return CloudEcho(
      files: reply.files, plus: reply.thresholds.plus, community: reply.thresholds.community,
      expireAt: reply.thresholds.expireAt)
  }
}
