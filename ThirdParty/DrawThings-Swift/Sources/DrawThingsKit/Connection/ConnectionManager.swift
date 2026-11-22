//
//  ConnectionManager.swift
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
import Observation

// MARK: - Connection State

/// Represents the current connection state.
public enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case error(String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    public var isConnecting: Bool {
        if case .connecting = self { return true }
        return false
    }

    public var errorMessage: String? {
        if case .error(let message) = self { return message }
        return nil
    }
}

// MARK: - Connection Manager

/// Manages server profiles and connection lifecycle for Draw Things applications.
///
/// This class handles:
/// - Storing and managing multiple server profiles
/// - Connecting to and disconnecting from servers
/// - Tracking connection state
/// - Managing the models catalog from the connected server
///
/// Example usage:
/// ```swift
/// @State private var connectionManager = ConnectionManager()
///
/// // Connect to a profile
/// await connectionManager.connect(to: profile)
///
/// // Generate on the connected server
/// if let service = connectionManager.activeService {
///     let result = try await service.generate(request)
/// }
/// ```
@MainActor
@Observable
public final class ConnectionManager {
    // MARK: - State

    /// All saved server profiles.
    public private(set) var profiles: [ServerProfile] = []

    /// The currently active profile (connected or attempting to connect).
    public private(set) var activeProfile: ServerProfile?

    /// Current connection state.
    public private(set) var connectionState: ConnectionState = .disconnected

    /// Models manager populated from the connected server.
    public let modelsManager = ModelsManager()

    /// Whether the connected server requires a shared secret that the profile doesn't have
    /// (or has wrong).
    public private(set) var serverRequiresSharedSecret: Bool = false

    // MARK: - Private Properties

    @ObservationIgnored private var service: DrawThingsService?
    @ObservationIgnored private let storage: ProfileStorage

    // MARK: - Initialization

    /// Initialize with optional custom storage.
    /// - Parameter storage: Custom ProfileStorage instance. Defaults to standard UserDefaults storage.
    public init(storage: ProfileStorage = ProfileStorage()) {
        self.storage = storage
        loadProfiles()
        DTLogger.debug("ConnectionManager initialized with \(profiles.count) profile(s)", category: .connection)
    }

    // MARK: - Public Properties

    /// The active DrawThingsService for making RPC calls.
    /// Returns nil if not connected.
    public var activeService: DrawThingsService? {
        guard connectionState.isConnected else { return nil }
        return service
    }

    /// The default profile, if one is set.
    public var defaultProfile: ServerProfile? {
        profiles.first { $0.isDefault }
    }

    // MARK: - Profile Management

    /// Add a new server profile.
    /// - Parameter profile: The profile to add.
    public func addProfile(_ profile: ServerProfile) {
        var newProfile = profile

        // If this is marked as default, clear default from others
        if newProfile.isDefault {
            clearDefaultFlag()
        }

        // If this is the first profile, make it default
        if profiles.isEmpty {
            newProfile.isDefault = true
        }

        profiles.append(newProfile)
        saveProfiles()
    }

    /// Update an existing profile.
    /// - Parameter profile: The updated profile.
    public func updateProfile(_ profile: ServerProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            return
        }

        let updatedProfile = profile

        // If this is marked as default, clear default from others
        if updatedProfile.isDefault {
            clearDefaultFlag(except: profile.id)
        }

        profiles[index] = updatedProfile
        saveProfiles()

        // If we updated the active profile, update our reference
        if activeProfile?.id == profile.id {
            activeProfile = updatedProfile
        }
    }

    /// Delete a profile.
    /// - Parameter profile: The profile to delete.
    public func deleteProfile(_ profile: ServerProfile) {
        // Disconnect if this is the active profile
        if activeProfile?.id == profile.id {
            disconnect()
        }

        profiles.removeAll { $0.id == profile.id }

        // If we deleted the default, make the first profile default
        if profile.isDefault, let first = profiles.first {
            var newDefault = first
            newDefault.isDefault = true
            if let index = profiles.firstIndex(where: { $0.id == first.id }) {
                profiles[index] = newDefault
            }
        }

        saveProfiles()
    }

    /// Set a profile as the default.
    /// - Parameter profile: The profile to set as default.
    public func setDefault(_ profile: ServerProfile) {
        clearDefaultFlag()

        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index].isDefault = true
            saveProfiles()
        }
    }

    // MARK: - Connection Management

    /// Connect to a server profile.
    /// - Parameter profile: The profile to connect to.
    public func connect(to profile: ServerProfile) async {
        DTLogger.info("Connecting to \(profile.name) at \(profile.address)...", category: .connection)

        // Close any existing or in-progress connection.
        if service != nil {
            disconnect()
        }

        activeProfile = profile
        connectionState = .connecting
        let newService = DrawThingsService(
            endpoint: ServerEndpoint(host: profile.host, port: profile.port),
            options: profile.connectionOptions
        )
        service = newService

        do {
            // Test the connection; this also checks the shared secret.
            let response = try await newService.echo(name: "DrawThingsKit")
            // A newer connect(to:) may have started while this one waited.
            guard service === newService else { return }
            serverRequiresSharedSecret = false

            // Update models from metadata
            if response.hasOverride {
                DTLogger.debug("Received metadata: models=\(response.override.models.count) bytes, loras=\(response.override.loras.count) bytes", category: .connection)
                modelsManager.updateFromMetadata(response.override)
                DTLogger.info("Loaded \(modelsManager.checkpoints.count) model(s), \(modelsManager.loras.count) LoRA(s)", category: .connection)
            } else {
                DTLogger.warning("Server response has no model metadata", category: .connection)
            }

            DTLogger.info("Connected to \(profile.name)", category: .connection)
            connectionState = .connected

        } catch {
            // A newer connect(to:) or disconnect() replaced this connection; nothing to report.
            guard service === newService else { return }
            DTLogger.error("Connection failed: \(error.localizedDescription)", category: .connection)
            if case DrawThingsError.unauthenticated = error {
                serverRequiresSharedSecret = true
            }
            service = nil
            Task { await newService.shutdown() }
            connectionState = .error(error.localizedDescription)
        }
    }

    /// Connect to the default profile, if one exists.
    public func connectToDefault() async {
        guard let defaultProfile = defaultProfile else {
            DTLogger.warning("No default profile configured", category: .connection)
            connectionState = .error("No default profile configured")
            return
        }
        DTLogger.debug("Connecting to default profile: \(defaultProfile.name)", category: .connection)
        await connect(to: defaultProfile)
    }

    /// Disconnect from the current server.
    public func disconnect() {
        if let profile = activeProfile {
            DTLogger.info("Disconnecting from \(profile.name)", category: .connection)
        } else {
            DTLogger.debug("Disconnect called with no active profile", category: .connection)
        }
        if let service {
            Task { await service.shutdown() }
        }
        service = nil
        activeProfile = nil
        connectionState = .disconnected
        serverRequiresSharedSecret = false
        modelsManager.clearLocalModels()
    }

    /// Attempt to reconnect to the active profile.
    public func reconnect() async {
        guard let profile = activeProfile else {
            DTLogger.debug("Reconnect called but no active profile", category: .connection)
            return
        }
        DTLogger.info("Reconnecting to \(profile.name)...", category: .connection)
        await connect(to: profile)
    }

    // MARK: - Private Methods

    private func loadProfiles() {
        profiles = storage.loadProfiles()

        // If no profiles exist, add a default localhost profile
        if profiles.isEmpty {
            addProfile(.localhost)
        }
    }

    private func saveProfiles() {
        storage.saveProfiles(profiles)
    }

    private func clearDefaultFlag(except excludeId: UUID? = nil) {
        for index in profiles.indices {
            if profiles[index].id != excludeId {
                profiles[index].isDefault = false
            }
        }
    }
}
