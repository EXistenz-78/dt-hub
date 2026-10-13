import Foundation

/// A list Draw Things publishes, downloaded once per launch and kept on disk: without the network, or when the site
/// does not answer, the saved copy is given. Only an answer that passes `isValid` replaces the saved copy, so an error
/// page costs nothing.
public actor CachedDownload {
  /// A download that failed is tried again after this long, not at every request.
  public static let retryAfter: TimeInterval = 10 * 60
  public static let maxBytes = 20_000_000

  private let address: URL
  private let cacheURL: URL
  private let isValid: @Sendable (Data) -> Bool
  private let download: @Sendable (URL) async throws -> Data
  private let now: @Sendable () -> Date
  private var known: Data?
  private var downloaded = false
  private var lastAttempt: Date?
  /// Grows each time `data()` has something new to give: who parses the data can keep what it parsed.
  public private(set) var generation = 0

  public init(
    address: URL, cacheURL: URL, isValid: @escaping @Sendable (Data) -> Bool,
    download: @escaping @Sendable (URL) async throws -> Data = CachedDownload.fetch,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.address = address
    self.cacheURL = cacheURL
    self.isValid = isValid
    self.download = download
    self.now = now
  }

  /// A file of the app's support folder (~/Library/Application Support/DT Hub).
  public static func supportFile(_ name: String) -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true)
      .appendingPathComponent(name)
  }

  /// The list: fresh when the download works, the saved copy otherwise; nil when there is neither.
  public func data() async -> Data? {
    if downloaded { return known }
    if let lastAttempt, now().timeIntervalSince(lastAttempt) < Self.retryAfter { return known }
    lastAttempt = now()
    if let fresh = try? await download(address), fresh.count <= Self.maxBytes, isValid(fresh) {
      try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? fresh.write(to: cacheURL, options: .atomic)
      if fresh != known { generation += 1 }
      known = fresh
      downloaded = true
      return fresh
    }
    if known == nil, let saved = try? Data(contentsOf: cacheURL), isValid(saved) {
      known = saved
      generation += 1
    }
    return known
  }

  /// One GET, with no cookies and no cache, given up after five seconds: nothing must wait long on it.
  public static let fetch: @Sendable (URL) async throws -> Data = { url in
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
