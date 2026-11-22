//
//  ServerEndpoint.swift
//  DrawThingsClient
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import Foundation

/// The host and port of a Draw Things gRPC server.
///
/// Parse one from a user-entered address with ``init(_:)``:
///
/// ```swift
/// try ServerEndpoint("192.168.1.20:7859")
/// try ServerEndpoint("studio.local")          // default port 7859
/// try ServerEndpoint("[fe80::1]:7859")        // bracketed IPv6
/// try ServerEndpoint("::1")                   // bare IPv6, default port
/// ```
public struct ServerEndpoint: Sendable, Hashable, CustomStringConvertible {
    /// The default Draw Things gRPC server port.
    public static let defaultPort = 7859

    /// Host name or IP address (IPv6 without brackets).
    public var host: String
    /// TCP port.
    public var port: Int

    public init(host: String, port: Int = ServerEndpoint.defaultPort) {
        self.host = host
        self.port = port
    }

    /// Parses `host`, `host:port`, `[ipv6]`, `[ipv6]:port` or a bare IPv6 address.
    /// A `grpc://` / `http(s)://` scheme prefix and a trailing `/` are ignored.
    public init(_ address: String) throws {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if let schemeRange = text.range(of: "://") {
            text = String(text[schemeRange.upperBound...])
        }
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty else { throw ServerEndpointError.emptyAddress }

        if text.hasPrefix("[") {
            // Bracketed IPv6: [addr] or [addr]:port
            guard let close = text.firstIndex(of: "]") else {
                throw ServerEndpointError.invalidAddress(address)
            }
            let host = String(text[text.index(after: text.startIndex)..<close])
            let rest = text[text.index(after: close)...]
            guard !host.isEmpty else { throw ServerEndpointError.invalidAddress(address) }
            if rest.isEmpty {
                self.init(host: host)
            } else if rest.hasPrefix(":") {
                self.init(host: host, port: try Self.parsePort(String(rest.dropFirst()), in: address))
            } else {
                throw ServerEndpointError.invalidAddress(address)
            }
            return
        }

        let colonCount = text.filter { $0 == ":" }.count
        switch colonCount {
        case 0:
            self.init(host: text)
        case 1:
            let parts = text.split(separator: ":", omittingEmptySubsequences: false)
            guard !parts[0].isEmpty else { throw ServerEndpointError.invalidAddress(address) }
            self.init(host: String(parts[0]), port: try Self.parsePort(String(parts[1]), in: address))
        default:
            // More than one colon without brackets: a bare IPv6 address.
            self.init(host: text)
        }
    }

    /// True for `localhost` and loopback IP addresses.
    public var isLoopback: Bool {
        let lower = host.lowercased()
        return lower == "localhost"
            || lower.hasSuffix(".localhost")
            || lower == "::1"
            || lower == "0:0:0:0:0:0:0:1"
            || lower.hasPrefix("127.")
    }

    /// True for hosts that can only be reached on the local network: loopback, private and
    /// shared IPv4 ranges (10/8, 172.16/12, 192.168/16, 100.64/10, 169.254/16), IPv6 unique-local
    /// and link-local addresses, `.local` (Bonjour) names and single-label host names.
    public var isLocalNetwork: Bool {
        if isLoopback { return true }
        let lower = host.lowercased()
        if isIPv6Literal {
            return lower.hasPrefix("fc") || lower.hasPrefix("fd") || lower.hasPrefix("fe8")
                || lower.hasPrefix("fe9") || lower.hasPrefix("fea") || lower.hasPrefix("feb")
        }
        let octets = lower.split(separator: ".").compactMap { UInt8($0) }
        if octets.count == 4 {
            switch (octets[0], octets[1]) {
            case (10, _), (192, 168), (169, 254): return true
            case (172, 16...31): return true
            case (100, 64...127): return true
            default: return false
            }
        }
        return lower.hasSuffix(".local") || !lower.contains(".")
    }

    /// True when `host` is an IPv6 literal.
    var isIPv6Literal: Bool { host.contains(":") }

    /// True when `host` is a dotted-quad IPv4 literal.
    var isIPv4Literal: Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil }
    }

    /// Resolves `host` to its IP addresses (as strings) without blocking the caller.
    /// Returns the host itself for IP literals and an empty array when resolution fails.
    func resolveAddresses() async -> [String] {
        if isIPv4Literal || isIPv6Literal { return [host] }
        let host = self.host
        return await Task.detached(priority: .userInitiated) {
            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC
            hints.ai_socktype = SOCK_STREAM
            var result: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return [] }
            defer { freeaddrinfo(first) }
            var addresses: [String] = []
            var cursor: UnsafeMutablePointer<addrinfo>? = first
            while let info = cursor {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, &buffer, socklen_t(buffer.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    // Drop any IPv6 zone suffix (fe80::1%en0).
                    let address = String(decoding: buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
                    addresses.append(String(address.split(separator: "%").first ?? ""))
                }
                cursor = info.pointee.ai_next
            }
            return addresses
        }.value
    }

    public var description: String {
        isIPv6Literal ? "[\(host)]:\(port)" : "\(host):\(port)"
    }

    private static func parsePort(_ text: String, in address: String) throws -> Int {
        guard let port = Int(text), (1...65535).contains(port) else {
            throw ServerEndpointError.invalidPort(address)
        }
        return port
    }
}

/// Errors thrown when parsing a ``ServerEndpoint``.
public enum ServerEndpointError: Error, Sendable, Equatable, LocalizedError {
    case emptyAddress
    case invalidAddress(String)
    case invalidPort(String)

    public var errorDescription: String? {
        switch self {
        case .emptyAddress: return "The server address is empty."
        case .invalidAddress(let address): return "“\(address)” is not a valid server address."
        case .invalidPort(let address): return "“\(address)” does not contain a valid port (1–65535)."
        }
    }
}
