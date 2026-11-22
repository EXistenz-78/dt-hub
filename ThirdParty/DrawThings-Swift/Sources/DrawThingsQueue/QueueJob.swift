//
//  QueueJob.swift
//  DrawThingsQueue
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import DrawThingsClient
import Foundation

/// A generation request and its state in a ``GenerationQueue``.
///
/// Jobs are values: the queue replaces a job as its state changes, so a copy you hold keeps the
/// state it had when you read it. Look it up again with ``GenerationQueue/job(_:)``.
public struct QueueJob: Sendable, Identifiable {
    /// Where a job is in its life cycle.
    public enum Status: Sendable, Hashable {
        case pending
        case running
        case completed
        case failed
        case cancelled

        /// True for completed, failed and cancelled jobs.
        public var isFinished: Bool {
            switch self {
            case .pending, .running: return false
            case .completed, .failed, .cancelled: return true
            }
        }
    }

    /// The request's ID.
    public var id: UUID { request.id }
    public internal(set) var request: GenerationRequest
    /// A display name; by default the start of the prompt.
    public internal(set) var name: String
    public let createdAt: Date
    public internal(set) var status: Status
    public internal(set) var startedAt: Date?
    public internal(set) var completedAt: Date?
    /// The result of a completed job.
    public internal(set) var result: GenerationResult?
    /// Why a failed job failed.
    public internal(set) var error: (any Error)?
    /// How many times the job has been retried after failing.
    public internal(set) var retryCount: Int

    init(request: GenerationRequest, name: String? = nil, createdAt: Date = Date(), retryCount: Int = 0) {
        self.request = request
        self.name = name ?? Self.name(fromPrompt: request.prompt)
        self.createdAt = createdAt
        self.status = .pending
        self.retryCount = retryCount
    }

    /// How long the job ran, once it has finished.
    public var duration: TimeInterval? {
        guard let startedAt, let completedAt else { return nil }
        return completedAt.timeIntervalSince(startedAt)
    }

    /// The first 50 characters of the prompt, cut at a word boundary.
    static func name(fromPrompt prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Untitled" }
        guard trimmed.count > 50 else { return trimmed }
        let prefix = trimmed.prefix(50)
        if let lastSpace = prefix.lastIndex(of: " ") {
            return prefix[..<lastSpace] + "..."
        }
        return prefix + "..."
    }
}

/// What happened in a ``GenerationQueue``, for observers outside SwiftUI.
public enum QueueEvent: Sendable {
    case added(QueueJob)
    case started(QueueJob)
    case progress(QueueJob.ID, GenerationProgress)
    case completed(QueueJob)
    case failed(QueueJob)
    case cancelled(QueueJob)
    case removed(QueueJob.ID)
    /// The queue paused, with the reason when it paused itself (for example, a lost connection).
    case paused(reason: String?)
    case resumed
}
