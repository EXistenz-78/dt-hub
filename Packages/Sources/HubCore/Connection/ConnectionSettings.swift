import Foundation

/// Where the Draw Things gRPC server is (spec §5). The shared secret is not here: it lives
/// in the Keychain (`SecretStore`).
public struct ConnectionSettings: Equatable, Codable, Sendable {
  public var host: String
  public var port: Int
  public var useTLS: Bool

  public init(host: String = "localhost", port: Int = 7859, useTLS: Bool = true) {
    self.host = host
    self.port = port
    self.useTLS = useTLS
  }

  public static let `default` = ConnectionSettings()

  public enum ValidationError: Equatable, Sendable {
    case emptyHost
    /// A URL, a path, a ":port" suffix or text with spaces instead of a host name or IP address.
    case invalidHost
    case invalidPort
  }

  private static func isIPv6Address(_ text: String) -> Bool {
    var address = in6_addr()
    return text.withCString { inet_pton(AF_INET6, $0, &address) } == 1
  }

  /// The port typed in a text field: digits only, spaces around allowed; nil otherwise.
  /// Range is not checked here: `validationError` reports it.
  public static func parsePort(_ text: String) -> Int? {
    let digits = text.trimmingCharacters(in: .whitespaces)
    guard !digits.isEmpty, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else { return nil }
    return Int(digits)
  }

  /// The host without surrounding spaces, as sent to the server.
  public var trimmedHost: String { host.trimmingCharacters(in: .whitespacesAndNewlines) }

  /// Why these settings cannot be used, or nil when they can.
  public var validationError: ValidationError? {
    let host = trimmedHost
    if host.isEmpty { return .emptyHost }
    if host.contains("://") || host.contains(where: \.isWhitespace) || host.contains("/") {
      return .invalidHost
    }
    // The server library dials any host with ":" as an IPv6 literal, so "host:port" or
    // "[::1]" would fail obscurely: only a bare IPv6 address may contain ":".
    if host.contains(":") && !Self.isIPv6Address(host) { return .invalidHost }
    if !(1...65535).contains(port) { return .invalidPort }
    return nil
  }
}

/// Persists `ConnectionSettings` in UserDefaults as JSON (spec §11).
public struct ConnectionSettingsStore {
  private let defaults: UserDefaults
  static let key = "drawThings.connection"

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// The saved settings; the defaults when nothing was saved or the data is unreadable.
  public func load() -> ConnectionSettings {
    guard let data = defaults.data(forKey: Self.key),
      let settings = try? JSONDecoder().decode(ConnectionSettings.self, from: data)
    else { return .default }
    return settings
  }

  public func save(_ settings: ConnectionSettings) {
    defaults.set(try? JSONEncoder().encode(settings), forKey: Self.key)
  }
}
