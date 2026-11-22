//
//  ConnectionOptions.swift
//  DrawThingsClient
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import Foundation
#if canImport(SystemConfiguration)
import SystemConfiguration
#endif

/// Options that control how ``DrawThingsService`` connects to a server.
public struct ConnectionOptions: Sendable {
    /// Transport security. Defaults to TLS with ``TransportSecurity/CertificateVerification/automatic``.
    public var security: TransportSecurity
    /// Shared secret sent with every request when the server requires one.
    public var sharedSecret: String?
    /// How this client identifies itself to the server.
    public var clientIdentity: ClientIdentity
    /// Largest single gRPC message sent or received. Requests carry full-size input tensors
    /// (a 2048×2048 image is 24 MiB) and responses carry 4 MiB chunks plus framing, so the
    /// gRPC default of 4 MiB is too small; the default here is 256 MiB.
    public var maxMessageBytes: Int
    /// Timeout for unary calls such as ``DrawThingsService/echo(name:)``. Generation calls are not
    /// limited, because they can legitimately take many minutes.
    public var requestTimeout: Duration
    /// Where model specifications come from. See ``ModelSpecSource``.
    public var modelSpecs: ModelSpecSource

    public init(
        security: TransportSecurity = .tls(),
        sharedSecret: String? = nil,
        clientIdentity: ClientIdentity = .default,
        maxMessageBytes: Int = 256 * 1024 * 1024,
        requestTimeout: Duration = .seconds(30),
        modelSpecs: ModelSpecSource = .bundled
    ) {
        self.security = security
        self.sharedSecret = sharedSecret
        self.clientIdentity = clientIdentity
        self.maxMessageBytes = maxMessageBytes
        self.requestTimeout = requestTimeout
        self.modelSpecs = modelSpecs
    }

    /// Default options: TLS, verifying certificates only for public (non-local-network) hosts.
    public static var `default`: ConnectionOptions { ConnectionOptions() }
}

/// How the connection to the server is secured.
public enum TransportSecurity: Sendable, Hashable {
    /// Unencrypted HTTP/2. Only use on trusted networks.
    case plaintext
    /// TLS with the given certificate verification policy.
    case tls(verification: CertificateVerification = .automatic)

    /// How the server's TLS certificate is verified.
    public enum CertificateVerification: Sendable, Hashable {
        /// Skip verification for local-network hosts (see ``ServerEndpoint/isLocalNetwork``),
        /// because the Draw Things app serves a self-signed certificate; verify fully against
        /// the system trust store for public hosts. Use ``trustRoots(_:)`` to verify a
        /// self-signed server reached over the internet.
        case automatic
        /// Always verify against the system trust store.
        case full
        /// Never verify. Traffic is encrypted but open to interception; only use this for a
        /// server you control on a trusted network.
        case none
        /// Verify against the given PEM-encoded root certificates instead of the system store,
        /// for example a remote Draw Things server's self-signed certificate.
        case trustRoots([Data])
    }
}

/// How the client identifies itself in generation requests. Draw Things shows the
/// user name in its UI while it serves the request.
public struct ClientIdentity: Sendable, Hashable {
    public var user: String
    public var device: DeviceType

    public init(user: String, device: DeviceType) {
        self.user = user
        self.device = device
    }

    /// The computer name on macOS (without a DNS lookup) and a generic name on iOS.
    public static let `default` = ClientIdentity(user: defaultUserName(), device: defaultDevice())

    private static func defaultUserName() -> String {
        #if os(macOS)
        if let name = SCDynamicStoreCopyComputerName(nil, nil) as String?, !name.isEmpty {
            return name
        }
        #endif
        return "DrawThingsClient"
    }

    private static func defaultDevice() -> DeviceType {
        #if os(macOS)
        return .laptop
        #else
        return .phone
        #endif
    }
}

/// Where the client finds model specifications, which Draw Things servers need in each
/// request to pick the right model version, latent space and sampler objective.
public enum ModelSpecSource: Sendable, Hashable {
    /// Use the server's reported specs and the snapshot bundled with this package.
    /// Makes no extra network requests.
    case bundled
    /// Also download the live model list the Draw Things app uses (once per process, on first
    /// need), so models released after this package version work without an update.
    case bundledAndRemote(URL = ModelSpecSource.drawThingsModelsURL)

    /// The model list the Draw Things app downloads at startup.
    public static let drawThingsModelsURL = URL(string: "https://models.drawthings.ai/models.json")!
}
