//
//  DrawThingsSession.swift
//  DrawThingsClient
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import CoreGraphics
import Foundation
import Observation

/// Observable connection state and generation progress for SwiftUI.
///
/// Wraps a `DrawThingsService` and mirrors its event stream into observable properties, so
/// views update as progress and previews arrive:
///
/// ```swift
/// @State private var session = try! DrawThingsSession(address: "localhost:7859")
///
/// var body: some View {
///     VStack {
///         if let progress = session.progress { ProgressView(value: progress.fractionCompleted ?? 0) }
///         if let preview = session.preview { Image(decorative: preview, scale: 1) }
///     }
///     .task { await session.connect() }
/// }
/// ```
///
/// One generation runs at a time; ``generate(_:)`` throws ``SessionError/busy`` while another is
/// in progress. For queueing, use `GenerationQueue` in the DrawThingsQueue product.
@MainActor
@Observable
public final class DrawThingsSession {
    /// The underlying service, for calls the session doesn't wrap.
    public let service: DrawThingsService

    /// Whether the last ``connect()`` succeeded.
    public private(set) var isConnected = false
    /// The server's reply to the last successful ``connect()``.
    public private(set) var serverInfo: EchoReply?
    /// True while a generation is running.
    public private(set) var isGenerating = false
    /// Progress of the running generation, or nil when idle.
    public private(set) var progress: GenerationProgress?
    /// The latest preview of the running generation, or nil when idle.
    public private(set) var preview: CGImage?
    /// Model files the server is downloading before it can start, when it reports them.
    public private(set) var remoteDownload: RemoteDownloadProgress?
    /// The last completed generation.
    public private(set) var lastResult: GenerationResult?
    /// The error from the last failed connection or generation; cleared when either succeeds.
    public private(set) var lastError: (any Error)?

    @ObservationIgnored private var generationTask: Task<GenerationResult, any Error>?

    public init(service: DrawThingsService) {
        self.service = service
    }

    /// Creates a session for a server address such as `"localhost:7859"`.
    public convenience init(address: String, options: ConnectionOptions = .default) throws {
        self.init(service: try DrawThingsService(address: address, options: options))
    }

    /// The latest preview as an `NSImage` / `UIImage`.
    public var previewImage: PlatformImage? { preview.map(PlatformImage.fromCGImage) }

    // MARK: - Connection

    /// Checks the connection, updating ``isConnected``, ``serverInfo`` and ``lastError``.
    public func connect() async {
        do {
            serverInfo = try await service.echo()
            isConnected = true
            lastError = nil
        } catch {
            isConnected = false
            lastError = error
        }
    }

    // MARK: - Generation

    /// Errors specific to the session.
    public enum SessionError: Error, Sendable, LocalizedError {
        /// A generation is already running.
        case busy

        public var errorDescription: String? {
            switch self {
            case .busy: return "A generation is already in progress."
            }
        }
    }

    /// Runs a generation, updating ``progress`` and ``preview`` as events arrive.
    ///
    /// Cancelling the calling task, or calling ``cancel()``, cancels the generation on the server
    /// and throws `CancellationError`.
    @discardableResult
    public func generate(_ request: GenerationRequest) async throws -> GenerationResult {
        guard generationTask == nil else { throw SessionError.busy }

        isGenerating = true
        progress = GenerationProgress(stage: .textEncoding, totalSteps: Int(request.configuration.steps))
        preview = nil
        remoteDownload = nil
        defer {
            isGenerating = false
            progress = nil
            preview = nil
            remoteDownload = nil
            generationTask = nil
        }

        let events = service.stream(request)
        let task = Task { @MainActor [weak self] in
            for try await event in events {
                switch event {
                case .progress(let progress): self?.progress = progress
                case .preview(let preview): self?.preview = preview
                case .remoteDownload(let download): self?.remoteDownload = download
                case .completed(let result): return result
                case .image, .audio: break
                }
            }
            throw CancellationError()
        }
        generationTask = task

        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            lastResult = result
            lastError = nil
            return result
        } catch {
            if !(error is CancellationError) { lastError = error }
            throw error
        }
    }

    /// Runs a generation from platform images. See ``generate(_:)``.
    @discardableResult
    public func generate(
        prompt: String,
        negativePrompt: String = "",
        configuration: DrawThingsConfiguration = DrawThingsConfiguration(),
        image: PlatformImage? = nil,
        mask: PlatformImage? = nil,
        hints: [HintProto] = []
    ) async throws -> GenerationResult {
        func upright(_ image: PlatformImage?) throws -> CGImage? {
            guard let image else { return nil }
            guard let cgImage = image.cgImageRepresentation else { throw ImageError.invalidImage }
            return cgImage
        }
        return try await generate(GenerationRequest(
            prompt: prompt,
            negativePrompt: negativePrompt,
            configuration: configuration,
            image: try upright(image),
            mask: try upright(mask),
            hints: hints
        ))
    }

    /// Cancels the running generation, if any.
    public func cancel() {
        generationTask?.cancel()
    }
}
