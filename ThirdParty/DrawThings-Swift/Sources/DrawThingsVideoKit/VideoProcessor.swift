//
//  VideoProcessor.swift
//  DrawThingsVideoKit
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

/// Events emitted by a ``VideoProcessor``.
public enum VideoProcessorEvent: Sendable {
    /// Frames were collected from a generation result.
    case framesCollected(jobId: UUID, count: Int)
    /// Video assembly started.
    case assemblyStarted(jobId: UUID)
    /// Video assembly progress (0.0 to 1.0).
    case assemblyProgress(jobId: UUID, progress: Double)
    /// Video assembly finished.
    case assemblyCompleted(jobId: UUID, outputURL: URL)
    /// Video assembly failed.
    case assemblyFailed(jobId: UUID, error: any Error)
}

/// Returns the video configuration for a job, for example to give each video its own file.
public typealias VideoConfigurationProvider = @Sendable (UUID) -> VideoConfiguration?

/// How a ``VideoProcessor`` handles incoming results.
public struct VideoProcessorConfiguration: Sendable {
    /// Whether to assemble a video as soon as a result's frames are collected.
    public var autoAssemble: Bool

    /// The fewest frames automatic assembly will turn into a video.
    public var minimumFrames: Int

    /// The video configuration used when ``configurationProvider`` is nil or returns nil.
    public var defaultVideoConfiguration: VideoConfiguration

    /// Whether to collect frames from every result, not only video results
    /// (`result.media.isVideo`).
    public var collectAllCompletedJobs: Bool

    /// Whether to clear the collected frames after automatic assembly succeeds. Set to `false`
    /// to keep them for reprocessing with different settings.
    public var clearFramesAfterAssembly: Bool

    /// Gives each job its own video configuration, such as an output URL named after the job.
    public var configurationProvider: VideoConfigurationProvider?

    public init(
        autoAssemble: Bool = false,
        minimumFrames: Int = 2,
        defaultVideoConfiguration: VideoConfiguration,
        collectAllCompletedJobs: Bool = false,
        clearFramesAfterAssembly: Bool = true,
        configurationProvider: VideoConfigurationProvider? = nil
    ) {
        self.autoAssemble = autoAssemble
        self.minimumFrames = minimumFrames
        self.defaultVideoConfiguration = defaultVideoConfiguration
        self.collectAllCompletedJobs = collectAllCompletedJobs
        self.clearFramesAfterAssembly = clearFramesAfterAssembly
        self.configurationProvider = configurationProvider
    }
}

/// Turns video generation results into video files.
///
/// Feed it results with ``connect(to:)`` (any async sequence of `GenerationResult`, such as a
/// `GenerationQueue`'s `results`) or ``ingest(_:)``. It collects each video result's frames and
/// audio, and with ``VideoProcessorConfiguration/autoAssemble`` encodes them at the model's
/// frame rate. You can also assemble frames yourself with ``assemble(frames:configuration:)``.
///
/// ```swift
/// let processor = VideoProcessor(configuration: VideoProcessorConfiguration(
///     autoAssemble: true,
///     defaultVideoConfiguration: VideoConfiguration(outputURL: outputURL)
/// ))
/// processor.connect(to: queue.results)
///
/// for await event in processor.events {
///     if case .assemblyCompleted(_, let url) = event { print("Video saved to \(url)") }
/// }
/// ```
///
/// The processor is `@Observable`; SwiftUI views that read ``collectedFrames``,
/// ``isAssembling`` or ``assemblyProgress`` update as it works.
@MainActor
@Observable
public final class VideoProcessor {
    /// Frames (and audio) collected from the latest video result.
    public private(set) var collectedFrames = VideoFrameCollection()

    /// True while a video is being assembled.
    public private(set) var isAssembling = false

    /// Progress of the current assembly (0.0 to 1.0).
    public private(set) var assemblyProgress: Double = 0

    /// The last assembled video.
    public private(set) var lastOutputURL: URL?

    /// The error from the last failed assembly; cleared when an assembly starts.
    public private(set) var lastError: (any Error)?

    /// How incoming results are handled.
    public var configuration: VideoProcessorConfiguration

    @ObservationIgnored private let assembler = VideoAssembler()
    @ObservationIgnored private let eventBroadcast = Broadcast<VideoProcessorEvent>()
    @ObservationIgnored private var connection: Task<Void, Never>?
    @ObservationIgnored private var autoAssembly: Task<Void, Never>?
    @ObservationIgnored private var activeAssemblies = 0

    public init(configuration: VideoProcessorConfiguration) {
        self.configuration = configuration
    }

    deinit {
        eventBroadcast.finish()
    }

    /// Processor events. Each access returns a new stream that receives events from then on.
    public var events: AsyncStream<VideoProcessorEvent> { eventBroadcast.subscribe() }

    // MARK: - Results

    /// Processes results from a sequence until it ends or ``disconnect()`` is called, replacing
    /// any earlier connection.
    public func connect<Results: AsyncSequence & Sendable>(to results: Results) where Results.Element == GenerationResult {
        disconnect()
        connection = Task { [weak self] in
            do {
                for try await result in results {
                    self?.ingest(result)
                }
            } catch {
                DTLogger.error("Video result sequence failed: \(error.localizedDescription)", category: .video)
            }
        }
    }

    /// Stops processing results from ``connect(to:)``.
    public func disconnect() {
        connection?.cancel()
        connection = nil
    }

    /// Collects a result's frames and audio if it is a video result (or
    /// ``VideoProcessorConfiguration/collectAllCompletedJobs`` is set), and assembles a video
    /// when ``VideoProcessorConfiguration/autoAssemble`` is set.
    ///
    /// Automatic assemblies run one at a time, in the order results arrive.
    public func ingest(_ result: GenerationResult) {
        guard configuration.collectAllCompletedJobs || result.media.isVideo else { return }
        addFrames(from: result)

        guard configuration.autoAssemble, collectedFrames.count >= configuration.minimumFrames else { return }
        var videoConfiguration = configuration.configurationProvider?(result.id) ?? configuration.defaultVideoConfiguration
        if let frameRate = result.media.frameRate {
            videoConfiguration.sourceFrameRate = frameRate
        }
        if videoConfiguration.audioData == nil, videoConfiguration.audioURL == nil {
            videoConfiguration.audioData = collectedFrames.audioData?.first
        }
        let frames = collectedFrames
        let jobId = result.id
        let previous = autoAssembly
        autoAssembly = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                try await self.assemble(frames: frames, configuration: videoConfiguration)
                if self.configuration.clearFramesAfterAssembly, self.collectedFrames.metadata.sourceJobId == jobId {
                    self.clearFrames()
                }
            } catch {
                DTLogger.error("Assembly failed: \(error.localizedDescription)", category: .video)
            }
        }
    }

    // MARK: - Frames

    /// Adds a result's frames and audio. Frames from an earlier job are cleared first, so
    /// frames from different generations aren't mixed.
    public func addFrames(from result: GenerationResult) {
        guard !result.images.isEmpty else { return }
        if let existing = collectedFrames.metadata.sourceJobId, existing != result.id {
            clearFrames()
        }

        var collection = collectedFrames
        collection.metadata.sourceJobId = result.id
        collection.metadata.prompt = result.request.prompt
        collection.metadata.negativePrompt = result.request.negativePrompt
        collection.metadata.model = result.request.configuration.model
        collection.metadata.seed = result.request.configuration.seed
        collection.metadata.generatedAt = result.completedAt
        for image in result.images {
            collection.append(cgImage: image)
        }
        if !result.audio.isEmpty {
            collection.audioData = (collection.audioData ?? []) + result.audio.map { $0.wavData() }
        }
        collectedFrames = collection

        eventBroadcast.send(.framesCollected(jobId: result.id, count: result.images.count))
    }

    /// Adds frames from image files.
    public func addFrames(from urls: [URL]) {
        for url in urls {
            collectedFrames.append(url: url)
        }
    }

    /// Adds the frames and audio of another collection.
    public func addFrames(from collection: VideoFrameCollection) {
        collectedFrames.append(contentsOf: collection)
    }

    /// Removes all collected frames and audio.
    public func clearFrames() {
        collectedFrames = VideoFrameCollection()
    }

    /// Removes frames at the given indices.
    public func removeFrames(at indices: IndexSet) {
        collectedFrames.remove(at: indices)
    }

    /// Replaces the collected frames.
    public func replaceFrames(with collection: VideoFrameCollection) {
        collectedFrames = collection
    }

    // MARK: - Assembly

    /// Assembles the collected frames.
    /// - Parameter configuration: Overrides ``VideoProcessorConfiguration/defaultVideoConfiguration``.
    /// - Returns: The URL of the video.
    @discardableResult
    public func assembleCollectedFrames(configuration: VideoConfiguration? = nil) async throws -> URL {
        try await assemble(frames: collectedFrames, configuration: configuration ?? self.configuration.defaultVideoConfiguration)
    }

    /// Assembles frames into a video, updating ``isAssembling`` and ``assemblyProgress``.
    /// - Returns: The URL of the video.
    @discardableResult
    public func assemble(frames: VideoFrameCollection, configuration: VideoConfiguration) async throws -> URL {
        let jobId = frames.metadata.sourceJobId ?? UUID()
        activeAssemblies += 1
        isAssembling = true
        assemblyProgress = 0
        lastError = nil
        eventBroadcast.send(.assemblyStarted(jobId: jobId))
        defer {
            activeAssemblies -= 1
            isAssembling = activeAssemblies > 0
        }

        do {
            let outputURL = try await assembler.assemble(frames: frames, configuration: configuration) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.report(progress, for: jobId)
                }
            }
            assemblyProgress = 1
            lastOutputURL = outputURL
            eventBroadcast.send(.assemblyCompleted(jobId: jobId, outputURL: outputURL))
            return outputURL
        } catch {
            lastError = error
            eventBroadcast.send(.assemblyFailed(jobId: jobId, error: error))
            throw error
        }
    }

    /// Assembles image files into a video.
    /// - Returns: The URL of the video.
    @discardableResult
    public func assemble(urls: [URL], configuration: VideoConfiguration) async throws -> URL {
        try await assemble(frames: VideoFrameCollection(urls: urls), configuration: configuration)
    }

    private func report(_ progress: Double, for jobId: UUID) {
        // Progress hops here in its own task, so it can arrive after the assembly finished.
        guard isAssembling else { return }
        assemblyProgress = progress
        eventBroadcast.send(.assemblyProgress(jobId: jobId, progress: progress))
    }
}
