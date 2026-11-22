//
//  SecretStore.swift
//  DrawThingsKit
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import Foundation
import Security

/// Where ``ProfileStorage`` keeps server shared secrets, one per account (a profile's ID).
public protocol SecretStore: Sendable {
    /// The secret for an account, or nil if none is stored.
    func secret(for account: String) throws -> String?
    /// Stores a secret for an account, or deletes it when `secret` is nil.
    func setSecret(_ secret: String?, for account: String) throws
}

/// A ``SecretStore`` in the Keychain: generic passwords under one service name, readable after
/// the device is first unlocked.
public struct KeychainSecretStore: SecretStore {
    /// The Keychain service name the secrets are stored under.
    public let service: String

    public init(service: String) {
        self.service = service
    }

    public func secret(for account: String) throws -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(decoding: data, as: UTF8.self)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    public func setSecret(_ secret: String?, for account: String) throws {
        guard let secret, !secret.isEmpty else {
            let status = SecItemDelete(baseQuery(account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
            return
        }
        let data = Data(secret.utf8)
        let status = SecItemUpdate(baseQuery(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery(account)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            item[kSecAttrLabel as String] = "Draw Things server shared secret"
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// A Keychain call failed.
public struct KeychainError: Error, LocalizedError, Sendable {
    /// The Security framework status code.
    public let status: OSStatus

    public var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
        return "Keychain error: \(message)"
    }
}
