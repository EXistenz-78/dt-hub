import Foundation

/// The list of official models Draw Things publishes (the one its app downloads at startup), so a model released
/// after this app was built is recognised without waiting for an update. Downloaded once per launch and kept on disk:
/// without the network, or when the site does not answer, the saved copy is used, and then the snapshot bundled with
/// DrawThings-Swift.
public actor LiveModelList {
  public static let address = URL(string: "https://models.drawthings.ai/models.json")!
  /// A download that failed is tried again after this long, not at every check of the connection.
  static let retryAfter: TimeInterval = 10 * 60
  static let maxBytes = 20_000_000

  /// The list of the app: ~/Library/Application Support/DT Hub/models-list.json.
  public static let shared = LiveModelList(
    cacheURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true)
      .appendingPathComponent("models-list.json"))

  private let cacheURL: URL
  private let address: URL
  private let download: @Sendable (URL) async throws -> Data
  private let now: @Sendable () -> Date
  private var known: [String: Data]?
  private var downloaded = false
  private var lastAttempt: Date?

  init(
    cacheURL: URL, address: URL = LiveModelList.address,
    download: @escaping @Sendable (URL) async throws -> Data = LiveModelList.fetch,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.cacheURL = cacheURL
    self.address = address
    self.download = download
    self.now = now
  }

  /// The specification of each model of the list, as its JSON object, by file name. Empty when the list was never
  /// downloaded.
  public func specs() async -> [String: Data] {
    if downloaded, let known { return known }
    if let lastAttempt, now().timeIntervalSince(lastAttempt) < Self.retryAfter, let known { return known }
    lastAttempt = now()
    if let data = try? await download(address), data.count <= Self.maxBytes {
      let fresh = Self.parse(data)
      // Only a real list replaces the saved copy: an error page must not cost the models it knew.
      if !fresh.isEmpty {
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
        known = fresh
        downloaded = true
        return fresh
      }
    }
    let saved = known ?? (try? Data(contentsOf: cacheURL)).map(Self.parse) ?? [:]
    known = saved
    return saved
  }

  /// A JSON array of specification objects; those without a `file` are skipped.
  static func parse(_ data: Data) -> [String: Data] {
    guard !data.isEmpty, let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [:] }
    var specs: [String: Data] = [:]
    for case let object as [String: Any] in array {
      guard let file = object["file"] as? String, !file.isEmpty, let json = try? JSONSerialization.data(withJSONObject: object)
      else { continue }
      specs[file] = json
    }
    return specs
  }

  /// One GET, with no cookies and no cache, given up after five seconds: the connection must not wait on it.
  static let fetch: @Sendable (URL) async throws -> Data = { url in
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    configuration.timeoutIntervalForRequest = 5
    configuration.timeoutIntervalForResource = 15
    let session = URLSession(configuration: configuration)
    defer { session.finishTasksAndInvalidate() }
    let (data, response) = try await session.data(from: url)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw URLError(.badServerResponse)
    }
    return data
  }
}
