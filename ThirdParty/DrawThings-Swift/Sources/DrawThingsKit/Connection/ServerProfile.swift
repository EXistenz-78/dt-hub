//
//  ServerProfile.swift
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

/// Represents a saved server connection profile.
public struct ServerProfile: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var useTLS: Bool
    public var sharedSecret: String?
    public var isDefault: Bool

    /// The full address string in "host:port" format (IPv6 hosts in brackets).
    public var address: String {
        ServerEndpoint(host: host, port: port).description
    }

    /// Connection options for this profile: TLS or plaintext, and the shared secret.
    public var connectionOptions: ConnectionOptions {
        ConnectionOptions(security: useTLS ? .tls() : .plaintext, sharedSecret: sharedSecret)
    }

    public init(
        id: UUID = UUID(),
        name: String,
        host: String = "localhost",
        port: Int = 7859,
        useTLS: Bool = true,
        sharedSecret: String? = nil,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.sharedSecret = sharedSecret
        self.isDefault = isDefault
    }

    /// Creates a profile from an address string (e.g., "localhost:7859").
    public init(name: String, address: String, useTLS: Bool = true, sharedSecret: String? = nil, isDefault: Bool = false) {
        self.id = UUID()
        self.name = name
        self.useTLS = useTLS
        self.sharedSecret = sharedSecret
        self.isDefault = isDefault

        if let endpoint = try? ServerEndpoint(address) {
            self.host = endpoint.host
            self.port = endpoint.port
        } else {
            self.host = address
            self.port = 7859
        }
    }
}

// MARK: - Default Profile

extension ServerProfile {
    /// A default localhost profile for convenience.
    public static var localhost: ServerProfile {
        ServerProfile(
            name: "Local Server",
            host: "localhost",
            port: 7859,
            useTLS: true,
            isDefault: true
        )
    }
}
