import CryptoKit
import Foundation

/// A release of Draw Things that carries the gRPCServerCLI: its tag, when it came out, and the sha256 of the program.
public struct ServerRelease: Equatable, Sendable {
  public let tag: String
  public let publishedAt: Date
  public let sha256: String

  public init(tag: String, publishedAt: Date, sha256: String) {
    self.tag = tag
    self.publishedAt = publishedAt
    self.sha256 = sha256
  }
}

/// What DT Hub can say about the gRPCServerCLI it starts. The server does not report its version, so the program is
/// recognized by its sha256 among the releases published on GitHub.
public struct ServerVersionInfo: Equatable, Sendable {
  public enum State: Equatable, Sendable {
    /// Nothing asked yet.
    case idle
    case checking
    /// No program chosen (or not a file): nothing to look at.
    case noProgram
    /// The program is the newest release.
    case upToDate
    /// A newer release exists.
    case updateAvailable
    /// The program is none of the recent releases (an older or a custom build): the latest is shown.
    case unidentified
    /// GitHub could not be reached; the version is the one remembered from the last time, if any.
    case couldNotCheck
  }

  public var state: State
  public var installed: String?
  public var latest: String?

  public init(state: State = .idle, installed: String? = nil, latest: String? = nil) {
    self.state = state
    self.installed = installed
    self.latest = latest
  }

  public static let idle = ServerVersionInfo()
}

/// Looks up the version of the gRPCServerCLI and whether a newer one is out.
public struct ServerVersionChecker: Sendable {
  /// The releases of Draw Things, newest first or not (they are sorted); nil when GitHub cannot be reached.
  public var releases: @Sendable () async -> [ServerRelease]?
  /// The sha256 of the program at a path; nil when it cannot be read.
  public var hash: @Sendable (String) async -> String?

  public init(
    releases: @escaping @Sendable () async -> [ServerRelease]?, hash: @escaping @Sendable (String) async -> String?
  ) {
    self.releases = releases
    self.hash = hash
  }

  /// `remembered` is the version the same program had the last time it was recognized: shown when GitHub is out of reach.
  public func check(programAt path: String, remembered: (hash: String, tag: String)? = nil) async -> (
    info: ServerVersionInfo, hash: String?
  ) {
    guard !path.isEmpty, let digest = await hash(path) else { return (ServerVersionInfo(state: .noProgram), nil) }
    guard let list = await releases(), !list.isEmpty else {
      let known = remembered?.hash == digest ? remembered?.tag : nil
      return (ServerVersionInfo(state: .couldNotCheck, installed: known), digest)
    }
    let latest = list.max { $0.publishedAt < $1.publishedAt }?.tag
    guard let match = list.first(where: { $0.sha256 == digest }) else {
      return (ServerVersionInfo(state: .unidentified, latest: latest), digest)
    }
    let state: ServerVersionInfo.State = match.tag == latest ? .upToDate : .updateAvailable
    return (ServerVersionInfo(state: state, installed: match.tag, latest: latest), digest)
  }

  /// The real one: GitHub's list of releases and the file read in chunks.
  public static let live = ServerVersionChecker(
    releases: { await GitHubReleases.fetch() },
    hash: { path in
      await Task.detached(priority: .utility) { sha256(ofFileAt: path) }.value
    })

  /// The sha256 of a file, read 4 MiB at a time (the program is about 250 MB).
  public static func sha256(ofFileAt path: String) -> String? {
    guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
    defer { try? handle.close() }
    var hasher = SHA256()
    do {
      // `read` gives nil, or empty data, at the end of the file.
      while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
        hasher.update(data: chunk)
      }
    } catch {
      return nil
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }
}

/// The public list of releases of drawthingsai/draw-things-community. One request, no account, nothing sent but the request.
enum GitHubReleases {
  static let url = URL(string: "https://api.github.com/repos/drawthingsai/draw-things-community/releases?per_page=30")!
  static let assetName = "gRPCServerCLI-macOS"

  static func fetch() async -> [ServerRelease]? {
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    guard let (data, response) = try? await URLSession.shared.data(for: request),
      (response as? HTTPURLResponse)?.statusCode == 200
    else { return nil }
    return parse(data)
  }

  static func parse(_ data: Data) -> [ServerRelease]? {
    struct Asset: Decodable {
      let name: String
      let digest: String?
    }
    struct Release: Decodable {
      let tag_name: String
      let published_at: Date?
      let draft: Bool?
      let prerelease: Bool?
      let assets: [Asset]
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let releases = try? decoder.decode([Release].self, from: data) else { return nil }
    return releases.compactMap { release in
      guard release.draft != true, release.prerelease != true, let date = release.published_at,
        let digest = release.assets.first(where: { $0.name == assetName })?.digest,
        digest.hasPrefix("sha256:")
      else { return nil }
      return ServerRelease(tag: release.tag_name, publishedAt: date, sha256: String(digest.dropFirst(7)))
    }
  }
}
