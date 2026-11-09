import Foundation
import Security

/// Where a secret is kept. The app uses the Keychain; tests use memory.
public protocol SecretStorage: Sendable {
  func read(_ key: String) -> String?
  func write(_ key: String, _ value: String)
}

public final class InMemorySecretStorage: SecretStorage, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String: String] = [:]
  public init() {}
  public func read(_ key: String) -> String? { lock.withLock { values[key] } }
  public func write(_ key: String, _ value: String) { lock.withLock { values[key] = value } }
}

/// The login Keychain, one generic-password item per key.
public struct KeychainSecretStorage: SecretStorage {
  private let service: String
  public init(service: String = "ai.dthub.mcp") { self.service = service }

  private func query(_ key: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
  }

  public func read(_ key: String) -> String? {
    var request = query(key)
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  public func write(_ key: String, _ value: String) {
    let data = Data(value.utf8)
    let update = SecItemUpdate(query(key) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if update == errSecItemNotFound {
      var add = query(key)
      add[kSecValueData as String] = data
      SecItemAdd(add as CFDictionary, nil)
    }
  }
}

/// The Bearer token a client must send (spec §6): random, kept in the Keychain, replaceable.
public struct TokenStore: Sendable {
  private static let key = "bearer-token"
  private let storage: any SecretStorage

  public init(storage: any SecretStorage) { self.storage = storage }

  public func token() -> String {
    if let existing = storage.read(Self.key), !existing.isEmpty { return existing }
    return regenerate()
  }

  @discardableResult
  public func regenerate() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    precondition(status == errSecSuccess, "no random bytes")
    let token = Data(bytes).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    storage.write(Self.key, token)
    return token
  }
}
