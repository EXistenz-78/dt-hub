import Foundation

/// What the request for the manifest gave.
public enum UpdateFetch: Equatable, Sendable {
  case ok(Data)
  /// HTTP 404: the release has no manifest (the ones before the automatic update).
  case missing
  /// No network, a timeout, any other answer.
  case failed
}

public enum UpdateCheckResult: Equatable, Sendable {
  case manifest(ReleaseManifest)
  /// GitHub answered but there is nothing this app can use.
  case noInformation
  case unreachable
}

/// Asks GitHub for the manifest of the newest release: one request, no account, nothing sent but the request.
public struct UpdateChecker: Sendable {
  public var fetch: @Sendable (URL) async -> UpdateFetch

  public init(fetch: @escaping @Sendable (URL) async -> UpdateFetch) {
    self.fetch = fetch
  }

  public func check(base: URL = UpdateEndpoint.base) async -> UpdateCheckResult {
    switch await fetch(UpdateEndpoint.manifestURL(base: base)) {
    case .failed: return .unreachable
    case .missing: return .noInformation
    case .ok(let data): return ReleaseManifest.parse(data).map(UpdateCheckResult.manifest) ?? .noInformation
    }
  }

  public static let live = UpdateChecker { url in
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    guard let (data, response) = try? await URLSession.shared.data(for: request),
      let status = (response as? HTTPURLResponse)?.statusCode
    else { return .failed }
    switch status {
    case 200: return .ok(data)
    case 404: return .missing
    default: return .failed
    }
  }
}
