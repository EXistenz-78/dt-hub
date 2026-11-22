//
//  GenerationQueue.swift
//  DrawThingsQueue
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import CoreGraphics
import DrawThingsClient
import Foundation
import Observation

/// Runs generation requests one at a time, in order.
///
/// The queue is `@Observable`: SwiftUI views that read ``pending``, ``current``, ``finished``,
/// ``progress`` or ``preview`` update as jobs move through it. Code outside SwiftUI can follow
/// ``events`` or ``results`` instead.
///
/// ```swift
/// let queue = GenerationQueue(service: try DrawThingsService(address: "localhost:7859"))
/// queue.enqueue(GenerationRequest(prompt: "A lighthouse at sunset", configuration: config))
/// for await result in queue.results {
///     save(result.images)
/// }
/// ```
///
/// If the server can't be reached, the job goes back to the front of the queue and the queue
/// pauses with a ``pauseReason``; call ``resume()`` to try again.
@MainActor
@Observable
public final class GenerationQueue {
    /// The service generations run on. Changing it affects jobs started afterwards.
    public var service: DrawThingsService

    /// Jobs waiting to run, in the order they will run.
    public private(set) var pending: [QueueJob] = []
    /// The running job.
    public private(set) var current: QueueJob?
    /// Completed, failed and cancelled jobs, oldest first, up to ``maxFinishedJobs``.
    public private(set) var finished: [QueueJob] = []

    /// Progress of the running job.
    public private(set) var progress: GenerationProgress?
    /// The latest preview of the running job.
    public private(set) var preview: CGImage?
    /// Model files the server is downloading for the running job, when it reports them.
    public private(set) var remoteDownload: RemoteDownloadProgress?

    /// True when the queue won't start new jobs. A running job finishes first.
    public private(set) var isPaused = false
    /// Why the queue paused itself, such as a lost connection; nil when paused by ``pause()``.
    public private(set) var pauseReason: String?

    /// How many finished jobs to keep; the oldest are dropped first.
    public var maxFinishedJobs = 50 {
        didSet { trimFinished() }
    }
    /// How many times a failed job can be retried.
    public var maxRetries = 3

    @ObservationIgnored private let storage: QueueStorage?
    @ObservationIgnored private var saveGeneration = 0
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private let eventBroadcast = Broadcast<QueueEvent>()
    @ObservationIgnored private let resultBroadcast = Broadcast<GenerationResult>()

    /// Creates a queue.
    /// - Parameters:
    ///   - service: The service generations run on.
    ///   - storage: Where pending jobs are saved, or nil to keep them only in memory. Call
    ///     ``restore()`` to reload them.
    public init(service: DrawThingsService, storage: QueueStorage? = nil) {
        self.service = service
        self.storage = storage
    }

    deinit {
        eventBroadcast.finish()
        resultBroadcast.finish()
    }

    // MARK: - State

    /// Finished, running and pending jobs, in that order.
    public var jobs: [QueueJob] {
        finished + (current.map { [$0] } ?? []) + pending
    }

    /// True while a job is running.
    public var isProcessing: Bool { current != nil }

    /// The job with this ID, wherever it is in the queue.
    public func job(_ id: QueueJob.ID) -> QueueJob? {
        if current?.id == id { return current }
        return pending.first { $0.id == id } ?? finished.last { $0.id == id }
    }

    /// Queue events. Each access returns a new stream that receives events from then on.
    public var events: AsyncStream<QueueEvent> { eventBroadcast.subscribe() }

    /// Results of completed jobs. Each access returns a new stream that receives results from
    /// then on.
    public var results: AsyncStream<GenerationResult> { resultBroadcast.subscribe() }

    // MARK: - Adding jobs

    /// Adds a request to the end of the queue.
    ///
    /// A configuration without a seed gets a random one, so the result can be reproduced.
    /// - Parameters:
    ///   - request: The generation to run.
    ///   - name: A display name; by default the start of the prompt.
    @discardableResult
    public func enqueue(_ request: GenerationRequest, name: String? = nil) -> QueueJob {
        let job = add(request, name: name)
        persist()
        startNextIfNeeded()
        return job
    }

    /// Adds requests to the end of the queue, in order.
    @discardableResult
    public func enqueue(contentsOf requests: [GenerationRequest]) -> [QueueJob] {
        let jobs = requests.map { add($0, name: nil) }
        persist()
        startNextIfNeeded()
        return jobs
    }

    private func add(_ request: GenerationRequest, name: String?) -> QueueJob {
        var request = request
        if request.configuration.seed == nil {
            request.configuration.seed = UInt32.random(in: 0...UInt32.max)
        }
        let job = QueueJob(request: request, name: name)
        pending.append(job)
        eventBroadcast.send(.added(job))
        return job
    }

    // MARK: - Controlling jobs

    /// Cancels a pending or running job. Returns false if the job isn't pending or running.
    @discardableResult
    public func cancel(_ id: QueueJob.ID) -> Bool {
        if let index = pending.firstIndex(where: { $0.id == id }) {
            var job = pending.remove(at: index)
            job.status = .cancelled
            job.completedAt = Date()
            appendFinished(job)
            eventBroadcast.send(.cancelled(job))
            persist()
            return true
        }
        if current?.id == id, let worker {
            worker.cancel()
            return true
        }
        return false
    }

    /// Cancels every pending job and the running job.
    public func cancelAll() {
        for job in pending { cancel(job.id) }
        if let current { cancel(current.id) }
    }

    /// Stops starting new jobs. A running job finishes first.
    public func pause() {
        pause(reason: nil)
    }

    /// Stops starting new jobs, recording why.
    public func pause(reason: String?) {
        isPaused = true
        pauseReason = reason
        eventBroadcast.send(.paused(reason: reason))
    }

    /// Starts running jobs again.
    public func resume() {
        guard isPaused else { return }
        isPaused = false
        pauseReason = nil
        eventBroadcast.send(.resumed)
        startNextIfNeeded()
    }

    /// Whether a job failed and has retries left.
    public func canRetry(_ id: QueueJob.ID) -> Bool {
        guard let job = finished.last(where: { $0.id == id }) else { return false }
        return job.status == .failed && job.retryCount < maxRetries
    }

    /// Puts a failed job back at the end of the queue. Returns false if it can't be retried.
    @discardableResult
    public func retry(_ id: QueueJob.ID) -> Bool {
        guard canRetry(id), let index = finished.lastIndex(where: { $0.id == id }) else { return false }
        let failed = finished.remove(at: index)
        let job = QueueJob(request: failed.request, name: failed.name, createdAt: failed.createdAt, retryCount: failed.retryCount + 1)
        pending.append(job)
        eventBroadcast.send(.added(job))
        persist()
        startNextIfNeeded()
        return true
    }

    /// Reorders pending jobs, with the same arguments as SwiftUI's `onMove`.
    public func movePending(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.filter { pending.indices.contains($0) }.map { pending[$0] }
        guard !moving.isEmpty else { return }
        let insertion = destination - source.count { $0 < destination }
        var remaining = pending
        for index in source.sorted(by: >) where remaining.indices.contains(index) {
            remaining.remove(at: index)
        }
        remaining.insert(contentsOf: moving, at: max(0, min(insertion, remaining.count)))
        pending = remaining
        persist()
    }

    /// Removes a pending or finished job. A running job must be cancelled instead.
    public func remove(_ id: QueueJob.ID) {
        if let index = pending.firstIndex(where: { $0.id == id }) {
            pending.remove(at: index)
            persist()
        } else if let index = finished.lastIndex(where: { $0.id == id }) {
            finished.remove(at: index)
        } else {
            return
        }
        eventBroadcast.send(.removed(id))
    }

    /// Removes completed jobs.
    public func clearCompleted() { finished.removeAll { $0.status == .completed } }

    /// Removes failed jobs.
    public func clearFailed() { finished.removeAll { $0.status == .failed } }

    /// Removes all finished jobs.
    public func clearFinished() { finished.removeAll() }

    /// Cancels everything and removes all finished jobs.
    public func clearAll() {
        cancelAll()
        finished.removeAll()
    }

    // MARK: - Persistence

    /// Loads jobs saved by an earlier run and adds them to the end of the queue.
    ///
    /// Reads files written by DrawThingsQueue 0.x as well; those didn't save input images or
    /// hints, so their jobs come back without them.
    public func restore() async throws {
        guard let storage else { return }
        let restored = try await storage.load()
        let known = Set(jobs.map(\.id))
        for job in restored where !known.contains(job.id) {
            pending.append(job)
            eventBroadcast.send(.added(job))
        }
        persist()
        startNextIfNeeded()
    }

    /// Saves the running and pending jobs. Encoding runs on the storage actor; a newer save
    /// supersedes an older one still waiting.
    private func persist() {
        guard let storage else { return }
        saveGeneration += 1
        let generation = saveGeneration
        var jobs = pending
        if var current {
            current.status = .pending
            jobs.insert(current, at: 0)
        }
        Task { await storage.save(jobs, generation: generation) }
    }

    // MARK: - Running

    private func startNextIfNeeded() {
        guard worker == nil, !isPaused, !pending.isEmpty else { return }
        var job = pending.removeFirst()
        job.status = .running
        job.startedAt = Date()
        current = job
        progress = GenerationProgress(stage: .textEncoding, totalSteps: Int(job.request.configuration.steps))
        preview = nil
        remoteDownload = nil
        eventBroadcast.send(.started(job))

        let events = service.stream(job.request)
        worker = Task { [weak self] in
            var outcome: Result<GenerationResult?, any Error>
            do {
                var result: GenerationResult?
                for try await event in events {
                    guard let self else { return }
                    switch event {
                    case .progress(let progress):
                        self.progress = progress
                        self.eventBroadcast.send(.progress(job.id, progress))
                    case .preview(let preview): self.preview = preview
                    case .remoteDownload(let download): self.remoteDownload = download
                    case .completed(let completed): result = completed
                    case .image, .audio: break
                    }
                }
                // The stream ends without a result when the task is cancelled.
                outcome = .success(Task.isCancelled ? nil : result)
            } catch {
                outcome = .failure(error)
            }
            self?.finish(job, outcome)
        }
    }

    private func finish(_ job: QueueJob, _ outcome: Result<GenerationResult?, any Error>) {
        var job = job
        job.completedAt = Date()
        worker = nil
        current = nil
        progress = nil
        preview = nil
        remoteDownload = nil

        switch outcome {
        case .success(let result?):
            job.status = .completed
            job.result = result
            appendFinished(job)
            eventBroadcast.send(.completed(job))
            resultBroadcast.send(result)
        case .success(nil), .failure(is CancellationError):
            job.status = .cancelled
            appendFinished(job)
            eventBroadcast.send(.cancelled(job))
        case .failure(DrawThingsError.connectionFailed(let detail)):
            // The server may come back: keep the job and wait for resume().
            job.status = .pending
            job.startedAt = nil
            job.completedAt = nil
            pending.insert(job, at: 0)
            DTLogger.warning("Queue paused: \(detail)", category: .queue)
            pause(reason: "Connection lost: \(detail)")
        case .failure(let error):
            job.status = .failed
            job.error = error
            appendFinished(job)
            DTLogger.error("Job \(job.name) failed: \(error.localizedDescription)", category: .queue)
            eventBroadcast.send(.failed(job))
        }
        persist()
        startNextIfNeeded()
    }

    private func appendFinished(_ job: QueueJob) {
        finished.append(job)
        trimFinished()
    }

    private func trimFinished() {
        let excess = finished.count - max(0, maxFinishedJobs)
        if excess > 0 { finished.removeFirst(excess) }
    }
}
