//
//  ProfileStorage.swift
//  DrawThingsKit
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import DrawThingsClient
import Foundation

/// Saves server profiles: the profiles in `UserDefaults`, their shared secrets in the Keychain.
///
/// Profiles are stored per app, under a key prefixed with the bundle identifier. Each shared secret
/// is a Keychain item keyed by its profile's ID. Secrets saved in `UserDefaults` by earlier
/// versions (DrawThingsKit 2.2 and DrawThings-Swift 2.0.0) are moved to the Keychain when loaded.
///
/// `@unchecked Sendable`: `UserDefaults` is documented as thread-safe, and the secret store is
/// `Sendable`.
public final class ProfileStorage: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let secrets: any SecretStore

    /// Creates storage.
    /// - Parameters:
    ///   - userDefaults: Where profiles are saved. Defaults to `.standard`.
    ///   - keyPrefix: The key prefix. Defaults to the app's bundle identifier.
    ///   - secrets: Where shared secrets are saved. Defaults to the Keychain, with the service
    ///     name `<keyPrefix>.serverProfiles`.
    public init(
        userDefaults: UserDefaults = .standard,
        keyPrefix: String? = nil,
        secrets: (any SecretStore)? = nil
    ) {
        self.userDefaults = userDefaults
        let prefix = keyPrefix ?? Bundle.main.bundleIdentifier ?? "DrawThingsKit"
        self.storageKey = "\(prefix).serverProfiles"
        self.secrets = secrets ?? KeychainSecretStore(service: storageKey)
    }

    /// Loads the saved profiles with their shared secrets.
    /// - Returns: The saved profiles, or an empty array if there are none.
    public func loadProfiles() -> [ServerProfile] {
        var profiles = storedProfiles()
        var migrated = false
        for index in profiles.indices {
            let account = profiles[index].id.uuidString
            if let plaintext = profiles[index].sharedSecret {
                // Saved by an earlier version: move it to the secret store.
                do {
                    try secrets.setSecret(plaintext, for: account)
                    migrated = true
                } catch {
                    DTLogger.error("Couldn't move a shared secret to the Keychain: \(error.localizedDescription)", category: .connection)
                }
            } else {
                do {
                    profiles[index].sharedSecret = try secrets.secret(for: account)
                } catch {
                    DTLogger.error("Couldn't read a shared secret from the Keychain: \(error.localizedDescription)", category: .connection)
                }
            }
        }
        if migrated {
            writeProfiles(profiles)
        }
        return profiles
    }

    /// Saves profiles, replacing the saved ones. Secrets of profiles no longer in the list are
    /// deleted.
    public func saveProfiles(_ profiles: [ServerProfile]) {
        let kept = Set(profiles.map(\.id))
        for removed in storedProfiles() where !kept.contains(removed.id) {
            try? secrets.setSecret(nil, for: removed.id.uuidString)
        }
        writeProfiles(profiles)
    }

    /// Deletes all saved profiles and their secrets.
    public func clearProfiles() {
        for profile in storedProfiles() {
            try? secrets.setSecret(nil, for: profile.id.uuidString)
        }
        userDefaults.removeObject(forKey: storageKey)
    }

    /// The profiles as saved in `UserDefaults`.
    private func storedProfiles() -> [ServerProfile] {
        guard let data = userDefaults.data(forKey: storageKey) else { return [] }
        do {
            return try JSONDecoder().decode([ServerProfile].self, from: data)
        } catch {
            DTLogger.error("Failed to decode profiles: \(error)", category: .connection)
            return []
        }
    }

    /// Saves each secret to the secret store and the profiles without them to `UserDefaults`.
    /// A secret the store can't take stays in `UserDefaults`, so it isn't lost.
    private func writeProfiles(_ profiles: [ServerProfile]) {
        let stored = profiles.map { profile -> ServerProfile in
            var profile = profile
            do {
                try secrets.setSecret(profile.sharedSecret, for: profile.id.uuidString)
                profile.sharedSecret = nil
            } catch {
                DTLogger.error("Couldn't save a shared secret to the Keychain; keeping it in UserDefaults: \(error.localizedDescription)", category: .connection)
            }
            return profile
        }
        do {
            userDefaults.set(try JSONEncoder().encode(stored), forKey: storageKey)
        } catch {
            DTLogger.error("Failed to encode profiles: \(error)", category: .connection)
        }
    }
}
