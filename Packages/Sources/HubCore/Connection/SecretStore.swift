import Foundation
import Security

/// Where the Draw Things shared secret is kept (spec §5, §11: the Keychain).
public protocol SecretStore: Sendable {
  func read() -> String?
  /// Saves the secret; nil or an empty string removes it.
  func write(_ secret: String?) throws
}

public struct KeychainError: Error, Equatable, Sendable {
  public let status: OSStatus
}

/// A generic-password Keychain item, one per service/account pair.
public struct KeychainSecretStore: SecretStore {
  let service: String
  let account: String

  public init(service: String = "com.exiztenz.DTHub", account: String = "drawThings.sharedSecret") {
    self.service = service
    self.account = account
  }

  private var query: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: service,
     kSecAttrAccount as String: account]
  }

  public func read() -> String? {
    var request = query
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  public func write(_ secret: String?) throws {
    let deleteStatus = SecItemDelete(query as CFDictionary)
    guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
      throw KeychainError(status: deleteStatus)
    }
    guard let secret, !secret.isEmpty else { return }
    var item = query
    item[kSecValueData as String] = Data(secret.utf8)
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else { throw KeychainError(status: status) }
  }
}
