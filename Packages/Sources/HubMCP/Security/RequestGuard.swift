import Foundation

public enum GuardDecision: Equatable, Sendable {
  case allow
  case unauthorized
  case forbiddenHost
  case forbiddenOrigin
}

/// Checks a request before the MCP SDK sees it (spec §6): the Host must be this Mac (against DNS rebinding),
/// no browser Origin is accepted (a web page must not call the server), and the Bearer token must match.
public struct RequestGuard: Sendable {
  private let token: String
  private let port: UInt16

  public init(token: String, port: UInt16) {
    self.token = token
    self.port = port
  }

  public func check(authorization: String?, host: String?, origin: String?) -> GuardDecision {
    guard let host, Self.isLoopback(host) else { return .forbiddenHost }
    if origin != nil { return .forbiddenOrigin }
    guard let authorization, authorization.hasPrefix("Bearer "),
      Self.constantTimeEqual(String(authorization.dropFirst("Bearer ".count)), token)
    else { return .unauthorized }
    return .allow
  }

  static func isLoopback(_ host: String) -> Bool {
    var name = host.lowercased()
    if name.hasPrefix("[") {
      guard let close = name.firstIndex(of: "]") else { return false }
      name = String(name[name.startIndex...close])
    } else if let colon = name.firstIndex(of: ":") {
      name = String(name[..<colon])
    }
    return ["127.0.0.1", "localhost", "[::1]"].contains(name)
  }

  static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
    let x = Array(a.utf8), y = Array(b.utf8)
    var difference = x.count ^ y.count
    for index in 0..<max(x.count, y.count) {
      difference |= Int(index < x.count ? x[index] : 0) ^ Int(index < y.count ? y[index] : 0)
    }
    return difference == 0
  }
}
