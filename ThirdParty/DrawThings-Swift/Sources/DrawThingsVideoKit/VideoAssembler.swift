//
//  VideoAssembler.swift
//  DrawThingsVideoKit
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import Foundation
import AVFoundation
import CoreGraphics
import CoreVideo
import DrawThingsClient
import VideoToolbox

/// Errors that can occur during video assembly.
public enum VideoAssemblerError: Error, LocalizedError, Sendable {
    case noFrames
    case inconsistentFrameSizes
    case failedToCreateWriter(Error?)
    case failedToCreateWriterInput
    case failedToCreatePixelBufferAdaptor
    case failedToCreatePixelBuffer
    case failedToStartWriting
    case failedToAppendFrame(Int)
    case failedToFinishWriting(Error?)
    case interpolationFailed(Error?)
    case superResolutionFailed(Error?)
    case outputFileExists
    case invalidConfiguration(String)
    case audioMuxingFailed(Error?)

    public var errorDescription: String? {
        switch self {
        case .noFrames:
            return "No frames provided for video assembly"
        case .inconsistentFrameSizes:
            return "All frames must have the same dimensions"
        case .failedToCreateWriter(let error):
            return "Failed to create video writer: \(error?.localizedDescription ?? "unknown error")"
        case .failedToCreateWriterInput:
            return "Failed to create video writer input"
        case .failedToCreatePixelBufferAdaptor:
            return "Failed to create pixel buffer adaptor"
        case .failedToCreatePixelBuffer:
            return "Failed to create pixel buffer from frame"
        case .failedToStartWriting:
            return "Failed to start video writing session"
        case .failedToAppendFrame(let index):
            return "Failed to append frame at index \(index)"
        case .failedToFinishWriting(let error):
            return "Failed to finish writing video: \(error?.localizedDescription ?? "unknown error")"
        case .interpolationFailed(let error):
            return "Frame interpolation failed: \(error?.localizedDescription ?? "unknown error")"
        case .superResolutionFailed(let error):
            return "Super resolution upscaling failed: \(error?.localizedDescription ?? "unknown error")"
        case .outputFileExists:
            return "Output file already exists and overwrite is disabled"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .audioMuxingFailed(let error):
            return "Audio muxing failed: \(error?.localizedDescription ?? "unknown error")"
        }
    }
}

/// Assembles video frames into a video file using AVFoundation.
///
/// VideoAssembler handles the low-level details of creating video files from
/// sequences of images, including codec selection, quality settings,
/// optional frame interpolation, and super resolution upscaling.
///
/// Frame interpolation uses Apple's VTFrameProcessor for motion-aware interpolation where
/// available (macOS 15.4+, iOS 26+), and super resolution uses VTSuperResolutionScaler for
/// ML upscaling (macOS 26+, iOS 26+). Elsewhere they fall back to Core Image.
///
/// Example usage:
/// ```swift
/// let assembler = VideoAssembler()
///
/// let config = VideoConfiguration(
///     outputURL: outputURL,
///     frameRate: 24,
///     interpolation: .enabled(factor: 2),
///     superResolution: .enabled(factor: 2)
/// )
///
/// let outputURL = try await assembler.assemble(
///     frames: frameCollection,
///     configuration: config
/// ) { progress in
///     print("Progress: \(progress * 100)%")
/// }
/// ```
public actor VideoAssembler {
    /// Frame interpolator instance.
    private let interpolator: FrameInterpolator

    /// Super resolution scaler instance.
    private let superResScaler: SuperResolutionScaler

    /// Creates a new video assembler.
    /// - Parameters:
    ///   - preferredInterpolationMethod: Optionally force a specific interpolation method.
    ///   - preferredSuperResolutionMethod: Optionally force a specific super resolution method.
    public init(
        preferredInterpolationMethod: InterpolationMethod? = nil,
        preferredSuperResolutionMethod: SuperResolutionMethod? = nil
    ) {
        self.interpolator = FrameInterpolator(preferredMethod: preferredInterpolationMethod)
        self.superResScaler = SuperResolutionScaler(preferredMethod: preferredSuperResolutionMethod)
    }

    /// The interpolation method that will be used.
    public var activeInterpolationMethod: InterpolationMethod {
        get async {
            await interpolator.activeMethod
        }
    }

    /// The super resolution method that will be used.
    public var activeSuperResolutionMethod: SuperResolutionMethod {
        get async {
            await superResScaler.activeMethod
        }
    }

    /// Assembles frames into a video file.
    ///
    /// - Parameters:
    ///   - frames: The frame collection to assemble.
    ///   - configuration: Video output configuration.
    ///   - progress: Optional progress callback (0.0 to 1.0).
    /// - Returns: The URL of the assembled video.
    /// - Throws: VideoAssemblerError if assembly fails.
    public func assemble(
        frames: VideoFrameCollection,
        configuration: VideoConfiguration,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        // Validate inputs
        guard !frames.isEmpty else {
            throw VideoAssemblerError.noFrames
        }

        // Handle existing file
        if FileManager.default.fileExists(atPath: configuration.outputURL.path) {
            if configuration.overwriteExisting {
                try FileManager.default.removeItem(at: configuration.outputURL)
            } else {
                throw VideoAssemblerError.outputFileExists
            }
        }

        // Load all CGImages
        let cgImages = frames.allCGImages()
        guard !cgImages.isEmpty else {
            throw VideoAssemblerError.noFrames
        }

        // Calculate progress segments
        let hasInterpolation = configuration.interpolation.isEnabled
        let hasSuperRes = configuration.superResolution.isEnabled
        let totalSteps = (hasInterpolation ? 1 : 0) + (hasSuperRes ? 1 : 0) + 1 // +1 for video writing
        var currentStep = 0

        /// Maps a stage's own 0...1 progress into its share of the overall progress.
        func stepProgress(_ step: Int) -> @Sendable (Double) -> Void {
            let stepSize = 1.0 / Double(totalSteps)
            let base = Double(step) * stepSize
            return { p in progress?(base + p * stepSize) }
        }

        var processedFrames = cgImages

        // Apply super resolution if enabled (before interpolation for better quality)
        if configuration.superResolution.isEnabled {
            do {
                processedFrames = try await superResScaler.upscale(
                    frames: processedFrames,
                    scaleFactor: configuration.superResolution.factor,
                    progress: stepProgress(currentStep)
                )
            } catch let error as SuperResolutionError {
                throw VideoAssemblerError.invalidConfiguration(error.localizedDescription)
            }
            currentStep += 1
        }

        // Apply interpolation if enabled
        if configuration.interpolation.isEnabled {
            do {
                processedFrames = try await interpolator.interpolate(
                    frames: processedFrames,
                    factor: configuration.interpolation.factor,
                    passMode: configuration.interpolationPassMode,
                    progress: stepProgress(currentStep)
                )
            } catch let error as FrameInterpolatorError {
                throw VideoAssemblerError.interpolationFailed(error)
            }
            currentStep += 1
        }

        // Assemble video
        let outputURL = try await writeVideo(
            frames: processedFrames,
            configuration: configuration,
            progress: stepProgress(currentStep)
        )

        return outputURL
    }

    // MARK: - Video Writing

    /// Writes frames to a video file.
    private func writeVideo(
        frames: [CGImage],
        configuration: VideoConfiguration,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> URL {
        guard let firstFrame = frames.first else {
            throw VideoAssemblerError.noFrames
        }

        let width = firstFrame.width
        let height = firstFrame.height

        // Verify all frames have the same size
        for frame in frames {
            if frame.width != width || frame.height != height {
                throw VideoAssemblerError.inconsistentFrameSizes
            }
        }

        // Resolve audio source URL (writes audioData to temp WAV if needed)
        let audioSourceURL = resolveAudioSource(configuration: configuration)

        // Create asset writer
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: configuration.outputURL, fileType: .mp4)
        } catch {
            throw VideoAssemblerError.failedToCreateWriter(error)
        }

        // Video settings
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: configuration.codec.avCodecType,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoQualityKey: configuration.quality.avQualityValue
            ]
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        guard writer.canAdd(writerInput) else {
            throw VideoAssemblerError.failedToCreateWriterInput
        }
        writer.add(writerInput)

        // Create pixel buffer adaptor
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        // Start writing
        guard writer.startWriting() else {
            throw VideoAssemblerError.failedToStartWriting
        }
        writer.startSession(atSourceTime: .zero)

        // Write frames
        // When interpolation is enabled, use the target frame rate directly (it's already the desired output).
        // When interpolation is disabled, use the source frame rate to maintain correct video duration.
        let effectiveFrameRate = configuration.interpolation.isEnabled
            ? configuration.frameRate
            : configuration.sourceFrameRate
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(effectiveFrameRate))

        for (index, frame) in frames.enumerated() {
            // Wait for input to be ready, checking for writer failure
            while !writerInput.isReadyForMoreMediaData {
                if writer.status == .failed {
                    throw VideoAssemblerError.failedToFinishWriting(writer.error ?? NSError(domain: "VideoAssembler", code: -1, userInfo: [NSLocalizedDescriptionKey: "Writer failed during frame writing at frame \(index)"]))
                }
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }

            let pixelBuffer = try createPixelBuffer(from: frame, width: width, height: height)
            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(index))

            guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                DTLogger.error("Appending frame \(index) failed: \(writer.error?.localizedDescription ?? "unknown")", category: .video)
                throw VideoAssemblerError.failedToAppendFrame(index)
            }

            progress?(Double(index + 1) / Double(frames.count))
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        if let error = writer.error {
            throw VideoAssemblerError.failedToFinishWriting(error)
        }

        // Mux audio in a separate pass using AVMutableComposition
        if let audioURL = audioSourceURL {
            defer {
                if configuration.audioData != nil {
                    try? FileManager.default.removeItem(at: audioURL)
                }
            }

            try await muxAudio(audioURL: audioURL, intoVideoAt: configuration.outputURL)
        }

        return configuration.outputURL
    }

    // MARK: - Pixel Buffer Helpers

    /// Creates a CVPixelBuffer from a CGImage with specified dimensions.
    private func createPixelBuffer(from image: CGImage, width: Int, height: Int) throws -> CVPixelBuffer {
        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            options as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw VideoAssemblerError.failedToCreatePixelBuffer
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            throw VideoAssemblerError.failedToCreatePixelBuffer
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return buffer
    }

    // MARK: - Audio Helpers

    /// Resolves the audio source URL from configuration.
    /// `audioData` takes precedence over `audioURL`. If `audioData` is set,
    /// writes it to a temp file and returns that URL.
    private func resolveAudioSource(configuration: VideoConfiguration) -> URL? {
        if let audioData = configuration.audioData {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("wav")
            do {
                try audioData.write(to: tempURL)
                return tempURL
            } catch {
                return nil
            }
        }
        return configuration.audioURL
    }

    /// Mux audio into an existing video file using AVMutableComposition.
    /// Replaces the video file in-place with a version containing both tracks.
    private func muxAudio(audioURL: URL, intoVideoAt videoURL: URL) async throws {
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)

        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
            return // No video track to mux into
        }
        guard let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            return // No audio track available
        }

        let composition = AVMutableComposition()

        // Add video track
        let videoDuration = try await videoAsset.load(.duration)
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoAssemblerError.audioMuxingFailed(nil)
        }
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoDuration),
            of: videoTrack,
            at: .zero
        )

        // Add audio track, trimmed to video duration
        guard let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoAssemblerError.audioMuxingFailed(nil)
        }
        let audioDuration = try await audioAsset.load(.duration)
        let insertDuration = CMTimeMinimum(audioDuration, videoDuration)
        try compositionAudioTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: insertDuration),
            of: audioTrack,
            at: .zero
        )

        // Export to a temp file, then replace the original
        let tempURL = videoURL.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw VideoAssemblerError.audioMuxingFailed(nil)
        }

        do {
            try await exportSession.export(to: tempURL, as: .mp4)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw VideoAssemblerError.audioMuxingFailed(error)
        }

        // Replace original video with muxed version
        let fm = FileManager.default
        try fm.removeItem(at: videoURL)
        try fm.moveItem(at: tempURL, to: videoURL)
    }
}
