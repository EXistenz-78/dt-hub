//
//  Broadcast.swift
//  DrawThingsClient
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import Foundation
import Synchronization

/// Delivers values to any number of `AsyncStream` subscribers. Shared by the package's
/// observable types for their `events` streams.
package final class Broadcast<Element: Sendable>: Sendable {
    private let continuations = Mutex<[UUID: AsyncStream<Element>.Continuation]>([:])

    package init() {}

    /// A new stream that receives values sent from now on.
    package func subscribe() -> AsyncStream<Element> {
        let (stream, continuation) = AsyncStream.makeStream(of: Element.self)
        let id = UUID()
        continuations.withLock { $0[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            _ = self?.continuations.withLock { $0.removeValue(forKey: id) }
        }
        return stream
    }

    package func send(_ value: Element) {
        for continuation in continuations.withLock({ Array($0.values) }) {
            continuation.yield(value)
        }
    }

    /// Ends every subscriber's stream.
    package func finish() {
        for continuation in continuations.withLock({ Array($0.values) }) {
            continuation.finish()
        }
    }
}
