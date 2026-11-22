//
//  DrawThingsError.swift
//  DrawThingsClient
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import Foundation
import GRPCCore

/// Errors thrown by DrawThingsClient.
public enum DrawThingsError: Error, Sendable, LocalizedError {
    /// The server could not be reached or the connection dropped.
    case connectionFailed(String)
    /// The server requires a shared secret, or the one sent was rejected.
    case unauthenticated
    /// A configuration value cannot be sent to the server.
    case invalidConfiguration(field: String, reason: String)
    /// Data from the server (or an input image) could not be decoded.
    case decodingFailed(String)
    /// The server finished without returning a complete result.
    case incompleteResponse(String)
    /// The server returned a gRPC error.
    case server(code: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let detail):
            return "Could not connect to the Draw Things server: \(detail)"
        case .unauthenticated:
            return "The Draw Things server requires a valid shared secret."
        case .invalidConfiguration(let field, let reason):
            return "Invalid configuration value for \(field): \(reason)"
        case .decodingFailed(let detail):
            return "Could not decode data: \(detail)"
        case .incompleteResponse(let detail):
            return "The server response was incomplete: \(detail)"
        case .server(let code, let message):
            return "The Draw Things server returned an error (\(code)): \(message)"
        }
    }

    /// Maps transport errors to ``DrawThingsError``. Cancellation is rethrown as
    /// `CancellationError` so callers can treat it like any other cancelled task.
    static func map(_ error: any Error) -> any Error {
        if error is DrawThingsError || error is CancellationError { return error }
        guard let rpcError = error as? RPCError else { return error }
        switch rpcError.code {
        case .cancelled:
            return CancellationError()
        case .unavailable, .deadlineExceeded:
            var detail = rpcError.message
            if detail.contains("connection preface") {
                // What a TLS/plaintext mismatch or a rejected certificate looks like from here.
                detail += " This usually means the TLS setting does not match the server's, or the server's certificate was rejected (use .tls(verification: .none) or .trustRoots for a self-signed server)."
            }
            return DrawThingsError.connectionFailed(detail)
        case .unauthenticated, .permissionDenied:
            return DrawThingsError.unauthenticated
        default:
            return DrawThingsError.server(code: String(describing: rpcError.code), message: rpcError.message)
        }
    }
}
