//
//  SuperResolutionScaler.swift
//  DrawThingsVideoKit
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import Foundation
import CoreImage
import CoreVideo
import CoreMedia
import VideoToolbox
import DrawThingsClient

/// Errors that can occur during super resolution scaling.
public enum SuperResolutionError: Error, LocalizedError, Sendable {
    case insufficientFrames
    case invalidScaleFactor
    case configurationFailed(String)
    case processingFailed(Error?)
    case pixelBufferCreationFailed
    case unsupportedOnSimulator
    case modelDownloadRequired
    case modelDownloadFailed(Error?)
    case frameTooLarge(width: Int, height: Int, maxWidth: Int, maxHeight: Int)

    public var errorDescription: String? {
        switch self {
        case .insufficientFrames:
            return "At least 1 frame is required for super resolution"
        case .invalidScaleFactor:
            return "Scale factor must be greater than 1"
        case .configurationFailed(let message):
            return "Super resolution configuration failed: \(message)"
        case .processingFailed(let error):
            return "Super resolution processing failed: \(error?.localizedDescription ?? "unknown error")"
        case .pixelBufferCreationFailed:
            return "Failed to create pixel buffer"
        case .unsupportedOnSimulator:
            return "VTSuperResolutionScaler is not available on simulator"
        case .modelDownloadRequired:
            return "ML model download is required before processing"
        case .modelDownloadFailed(let error):
            return "ML model download failed: \(error?.localizedDescription ?? "unknown error")"
        case .frameTooLarge(let width, let height, let maxWidth, let maxHeight):
            return "Frame size \(width)x\(height) exceeds maximum \(maxWidth)x\(maxHeight) for super resolution"
        }
    }
}

/// Method used for super resolution scaling.
public enum SuperResolutionMethod: String, Sendable {
    /// Apple's VTSuperResolutionScaler ML-based upscaling (macOS 26+, iOS 26+).
    /// Provides high-quality temporal-aware upscaling for video.
    case vtSuperResolution

    /// Apple's VTLowLatencySuperResolutionScaler (macOS 26+, iOS 26+).
    /// Faster processing with lower latency, suitable for real-time use.
    case vtLowLatency

    /// Core Image Lanczos scaling.
    /// Available on all OS versions, good quality bicubic-like scaling.
    case coreImageLanczos
}

/// Status of ML model availability for super resolution.
public enum SuperResolutionModelStatus: Sendable {
    /// Models need to be downloaded before use.
    case downloadRequired
    /// Models are currently being downloaded.
    case downloading(progress: Float)
    /// Models are ready to use.
    case ready
    /// Not applicable (using Core Image fallback or low-latency mode).
    case notApplicable
}

/// Super resolution scaler that uses VTSuperResolutionScaler on macOS 26+ with Core Image fallback.
///
/// On macOS 26+ and iOS 26+, this uses Apple's ML-based VTSuperResolutionScaler
/// for high-quality temporal upscaling. On older systems, it falls back to
/// Core Image Lanczos scaling.
///
/// Example usage:
/// ```swift
/// let scaler = SuperResolutionScaler()
/// let upscaledFrames = try await scaler.upscale(
///     frames: originalFrames,
///     scaleFactor: 2
/// )
/// ```
public actor SuperResolutionScaler {
    /// Core Image context for fallback scaling.
    private let ciContext: CIContext

    /// Force using a specific super resolution method (nil = auto-select best available).
    public var preferredMethod: SuperResolutionMethod?

    /// Creates a new super resolution scaler.
    /// - Parameter preferredMethod: Optionally force a specific scaling method.
    public init(preferredMethod: SuperResolutionMethod? = nil) {
        self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
        self.preferredMethod = preferredMethod
    }

    /// Returns the super resolution method that will be used.
    public var activeMethod: SuperResolutionMethod {
        if let preferred = preferredMethod {
            return preferred
        }

        if #available(macOS 26.0, iOS 26.0, *) {
            #if !targetEnvironment(simulator)
            if VTSuperResolutionScalerConfiguration.isSupported {
                return .vtSuperResolution
            } else if VTLowLatencySuperResolutionScalerConfiguration.isSupported {
                return .vtLowLatency
            }
            #endif
        }

        return .coreImageLanczos
    }

    /// Checks if VT-based super resolution is available.
    public static var isVTSuperResolutionAvailable: Bool {
        if #available(macOS 26.0, iOS 26.0, *) {
            #if !targetEnvironment(simulator)
            return VTSuperResolutionScalerConfiguration.isSupported
            #else
            return false
            #endif
        }
        return false
    }

    /// Checks if VT low-latency super resolution is available.
    public static var isVTLowLatencyAvailable: Bool {
        if #available(macOS 26.0, iOS 26.0, *) {
            #if !targetEnvironment(simulator)
            return VTLowLatencySuperResolutionScalerConfiguration.isSupported
            #else
            return false
            #endif
        }
        return false
    }

    // MARK: - Model Status and Download

    /// Gets the current model status for VT super resolution.
    ///
    /// - Parameters:
    ///   - width: Source frame width (used for configuration).
    ///   - height: Source frame height (used for configuration).
    ///   - scaleFactor: Scale factor to use.
    /// - Returns: The current model status.
    public static func modelStatus(
        forWidth width: Int = 512,
        height: Int = 512,
        scaleFactor: Int = 2
    ) -> SuperResolutionModelStatus {
        guard isVTSuperResolutionAvailable else {
            return .notApplicable
        }

        if #available(macOS 26.0, iOS 26.0, *) {
            #if !targetEnvironment(simulator)
            guard let configuration = VTSuperResolutionScalerConfiguration(
                frameWidth: width,
                frameHeight: height,
                scaleFactor: scaleFactor,
                inputType: .video,
                usePrecomputedFlow: false,
                qualityPrioritization: .normal,
                revision: .revision1
            ) else {
                return .notApplicable
            }

            switch configuration.configurationModelStatus {
            case .downloadRequired:
                return .downloadRequired
            case .downloading:
                return .downloading(progress: configuration.configurationModelPercentageAvailable)
            case .ready:
                return .ready
            @unknown default:
                return .notApplicable
            }
            #else
            return .notApplicable
            #endif
        }
        return .notApplicable
    }

    /// Downloads the ML models required for VT super resolution.
    ///
    /// - Parameters:
    ///   - width: Source frame width (used for configuration).
    ///   - height: Source frame height (used for configuration).
    ///   - scaleFactor: Scale factor to use.
    ///   - progress: Optional progress callback (0.0 to 1.0).
    /// - Throws: SuperResolutionError if download fails.
    public static func downloadModels(
        forWidth width: Int = 512,
        height: Int = 512,
        scaleFactor: Int = 2,
        progress: (@Sendable (Float) -> Void)? = nil
    ) async throws {
        guard isVTSuperResolutionAvailable else {
            return // Nothing to download
        }

        if #available(macOS 26.0, iOS 26.0, *) {
            #if !targetEnvironment(simulator)
            guard let configuration = VTSuperResolutionScalerConfiguration(
                frameWidth: width,
                frameHeight: height,
                scaleFactor: scaleFactor,
                inputType: .video,
                usePrecomputedFlow: false,
                qualityPrioritization: .normal,
                revision: .revision1
            ) else {
                throw SuperResolutionError.configurationFailed("Failed to create configuration for model download")
            }

            // Check if already ready
            if configuration.configurationModelStatus == .ready {
                progress?(1.0)
                return
            }

            // Start download and poll for progress
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                configuration.downloadConfigurationModel { error in
                    if let error = error {
                        continuation.resume(throwing: SuperResolutionError.modelDownloadFailed(error))
                    } else {
                        continuation.resume()
                    }
                }
            }

            progress?(1.0)
            #endif
        }
    }

    /// Returns supported scale factors for the active method.
    /// - Parameters:
    ///   - width: Source frame width.
    ///   - height: Source frame height.
    /// - Returns: Array of supported scale factors.
    public func supportedScaleFactors(forWidth width: Int, height: Int) -> [Int] {
        let method = activeMethod

        switch method {
        case .vtSuperResolution:
            if #available(macOS 26.0, iOS 26.0, *) {
                #if !targetEnvironment(simulator)
                return VTSuperResolutionScalerConfiguration.supportedScaleFactors
                #endif
            }
            return [2] // Default fallback

        case .vtLowLatency:
            if #available(macOS 26.0, iOS 26.0, *) {
                #if !targetEnvironment(simulator)
                let factors = VTLowLatencySuperResolutionScalerConfiguration.supportedScaleFactors(
                    frameWidth: width,
                    frameHeight: height
                )
                return factors.map { Int($0) }
                #endif
            }
            return [2] // Default fallback

        case .coreImageLanczos:
            // Core Image can scale to any factor
            return [2, 3, 4]
        }
    }

    /// Upscales frames using super resolution.
    ///
    /// - Parameters:
    ///   - frames: Array of CGImages to upscale.
    ///   - scaleFactor: Scale factor (2 = double resolution, etc.).
    ///   - progress: Optional progress callback (0.0 to 1.0).
    /// - Returns: Array of upscaled CGImages.
    /// - Throws: SuperResolutionError if upscaling fails.
    public func upscale(
        frames: [CGImage],
        scaleFactor: Int,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [CGImage] {
        guard !frames.isEmpty else {
            throw SuperResolutionError.insufficientFrames
        }

        guard scaleFactor > 1 else {
            throw SuperResolutionError.invalidScaleFactor
        }

        let method = activeMethod

        switch method {
        case .vtSuperResolution:
            if #available(macOS 26.0, iOS 26.0, *) {
                #if !targetEnvironment(simulator)
                do {
                    return try await upscaleWithVTSuperResolution(
                        frames: frames,
                        scaleFactor: scaleFactor,
                        progress: progress
                    )
                } catch {
                    // Log the error and fall back to Core Image
                    DTLogger.warning("VT super resolution failed: \(error.localizedDescription). Falling back to Core Image.", category: .video)
                    return try upscaleWithCoreImage(
                        frames: frames,
                        scaleFactor: scaleFactor,
                        progress: progress
                    )
                }
                #else
                throw SuperResolutionError.unsupportedOnSimulator
                #endif
            } else {
                return try upscaleWithCoreImage(
                    frames: frames,
                    scaleFactor: scaleFactor,
                    progress: progress
                )
            }

        case .vtLowLatency:
            if #available(macOS 26.0, iOS 26.0, *) {
                #if !targetEnvironment(simulator)
                do {
                    return try await upscaleWithVTLowLatency(
                        frames: frames,
                        scaleFactor: scaleFactor,
                        progress: progress
                    )
                } catch {
                    // Log the error and fall back to Core Image
                    DTLogger.warning("VT low latency failed: \(error.localizedDescription). Falling back to Core Image.", category: .video)
                    return try upscaleWithCoreImage(
                        frames: frames,
                        scaleFactor: scaleFactor,
                        progress: progress
                    )
                }
                #else
                throw SuperResolutionError.unsupportedOnSimulator
                #endif
            } else {
                return try upscaleWithCoreImage(
                    frames: frames,
                    scaleFactor: scaleFactor,
                    progress: progress
                )
            }

        case .coreImageLanczos:
            return try upscaleWithCoreImage(
                frames: frames,
                scaleFactor: scaleFactor,
                progress: progress
            )
        }
    }

    // MARK: - VT Super Resolution Implementation

    #if !targetEnvironment(simulator)
    @available(macOS 26.0, iOS 26.0, *)
    private func upscaleWithVTSuperResolution(
        frames: [CGImage],
        scaleFactor: Int,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> [CGImage] {
        guard let firstFrame = frames.first else {
            throw SuperResolutionError.insufficientFrames
        }

        let width = firstFrame.width
        let height = firstFrame.height

        // Check size limits (max 1920x1080 for video)
        let maxWidth = 1920
        let maxHeight = 1080
        if width > maxWidth || height > maxHeight {
            throw SuperResolutionError.frameTooLarge(
                width: width,
                height: height,
                maxWidth: maxWidth,
                maxHeight: maxHeight
            )
        }

        // Check supported scale factors
        let supportedFactors = VTSuperResolutionScalerConfiguration.supportedScaleFactors
        guard supportedFactors.contains(scaleFactor) else {
            throw SuperResolutionError.configurationFailed(
                "Scale factor \(scaleFactor) not supported. Supported factors: \(supportedFactors)"
            )
        }

        // Create configuration
        guard let configuration = VTSuperResolutionScalerConfiguration(
            frameWidth: width,
            frameHeight: height,
            scaleFactor: scaleFactor,
            inputType: .video,
            usePrecomputedFlow: false,
            qualityPrioritization: .normal,
            revision: .revision1
        ) else {
            throw SuperResolutionError.configurationFailed(
                "Failed to create VTSuperResolutionScalerConfiguration for \(width)x\(height) at \(scaleFactor)x. " +
                "Supported scale factors: \(supportedFactors). " +
                "Check that dimensions are within limits (max 1920x1080 for video)."
            )
        }

        // Check model status and download if needed
        if configuration.configurationModelStatus == .downloadRequired {
            try await downloadModel(configuration: configuration)
        }

        // Create processor and start session
        let processor = VTFrameProcessor()
        try processor.startSession(configuration: configuration)
        defer { processor.endSession() }

        var result: [CGImage] = []
        let outputWidth = width * scaleFactor
        let outputHeight = height * scaleFactor

        var previousSourceBuffer: CVPixelBuffer?
        var previousOutputBuffer: CVPixelBuffer?

        for (index, frame) in frames.enumerated() {
            // Create source pixel buffer
            let sourceBuffer = try createIOSurfaceBackedPixelBuffer(from: frame)

            // Create destination buffer at scaled size
            let destBuffer = try createIOSurfaceBackedPixelBuffer(
                width: outputWidth,
                height: outputHeight
            )

            // Create VTFrameProcessorFrame objects
            let sourceTime = CMTime(value: CMTimeValue(index), timescale: 1)
            guard let sourceFrame = VTFrameProcessorFrame(buffer: sourceBuffer, presentationTimeStamp: sourceTime),
                  let destFrame = VTFrameProcessorFrame(buffer: destBuffer, presentationTimeStamp: sourceTime) else {
                throw SuperResolutionError.pixelBufferCreationFailed
            }

            // Create previous frames if available
            var previousFrame: VTFrameProcessorFrame?
            var previousOutput: VTFrameProcessorFrame?

            if let prevSource = previousSourceBuffer {
                let prevTime = CMTime(value: CMTimeValue(index - 1), timescale: 1)
                previousFrame = VTFrameProcessorFrame(buffer: prevSource, presentationTimeStamp: prevTime)
            }

            if let prevOutput = previousOutputBuffer {
                let prevTime = CMTime(value: CMTimeValue(index - 1), timescale: 1)
                previousOutput = VTFrameProcessorFrame(buffer: prevOutput, presentationTimeStamp: prevTime)
            }

            // Create parameters
            let submissionMode: VTSuperResolutionScalerParameters.SubmissionMode = index == 0 ? .random : .sequential

            guard let parameters = VTSuperResolutionScalerParameters(
                sourceFrame: sourceFrame,
                previousFrame: previousFrame,
                previousOutputFrame: previousOutput,
                opticalFlow: nil,
                submissionMode: submissionMode,
                destinationFrame: destFrame
            ) else {
                throw SuperResolutionError.configurationFailed("Failed to create parameters")
            }

            // Process frame
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                processor.process(parameters: parameters) { _, error in
                    if let error = error {
                        continuation.resume(throwing: SuperResolutionError.processingFailed(error))
                    } else {
                        continuation.resume()
                    }
                }
            }

            // Extract result
            if let cgImage = createCGImage(from: destBuffer) {
                result.append(cgImage)
            }

            // Store for next iteration
            previousSourceBuffer = sourceBuffer
            previousOutputBuffer = destBuffer

            progress?(Double(index + 1) / Double(frames.count))
        }

        return result
    }

    @available(macOS 26.0, iOS 26.0, *)
    private func downloadModel(configuration: VTSuperResolutionScalerConfiguration) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            configuration.downloadConfigurationModel { error in
                if let error = error {
                    continuation.resume(throwing: SuperResolutionError.modelDownloadFailed(error))
                } else {
                    continuation.resume()
                }
            }
        }
    }
    #endif

    // MARK: - VT Low Latency Implementation

    #if !targetEnvironment(simulator)
    @available(macOS 26.0, iOS 26.0, *)
    private func upscaleWithVTLowLatency(
        frames: [CGImage],
        scaleFactor: Int,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> [CGImage] {
        guard let firstFrame = frames.first else {
            throw SuperResolutionError.insufficientFrames
        }

        let width = firstFrame.width
        let height = firstFrame.height

        // Create configuration
        let configuration = VTLowLatencySuperResolutionScalerConfiguration(
            frameWidth: width,
            frameHeight: height,
            scaleFactor: Float(scaleFactor)
        )

        // Create processor and start session
        let processor = VTFrameProcessor()
        try processor.startSession(configuration: configuration)
        defer { processor.endSession() }

        var result: [CGImage] = []
        let outputWidth = width * scaleFactor
        let outputHeight = height * scaleFactor

        for (index, frame) in frames.enumerated() {
            // Create source pixel buffer
            let sourceBuffer = try createIOSurfaceBackedPixelBuffer(from: frame)

            // Create destination buffer at scaled size
            let destBuffer = try createIOSurfaceBackedPixelBuffer(
                width: outputWidth,
                height: outputHeight
            )

            // Create VTFrameProcessorFrame objects
            let frameTime = CMTime(value: CMTimeValue(index), timescale: 1)
            guard let sourceFrame = VTFrameProcessorFrame(buffer: sourceBuffer, presentationTimeStamp: frameTime),
                  let destFrame = VTFrameProcessorFrame(buffer: destBuffer, presentationTimeStamp: frameTime) else {
                throw SuperResolutionError.pixelBufferCreationFailed
            }

            // Create parameters
            let parameters = VTLowLatencySuperResolutionScalerParameters(
                sourceFrame: sourceFrame,
                destinationFrame: destFrame
            )

            // Process frame
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                processor.process(parameters: parameters) { _, error in
                    if let error = error {
                        continuation.resume(throwing: SuperResolutionError.processingFailed(error))
                    } else {
                        continuation.resume()
                    }
                }
            }

            // Extract result
            if let cgImage = createCGImage(from: destBuffer) {
                result.append(cgImage)
            }

            progress?(Double(index + 1) / Double(frames.count))
        }

        return result
    }
    #endif

    // MARK: - Core Image Implementation (Fallback)

    private func upscaleWithCoreImage(
        frames: [CGImage],
        scaleFactor: Int,
        progress: (@Sendable (Double) -> Void)?
    ) throws -> [CGImage] {
        var result: [CGImage] = []

        for (index, frame) in frames.enumerated() {
            let upscaled = try upscaleFrame(frame, scaleFactor: scaleFactor)
            result.append(upscaled)

            progress?(Double(index + 1) / Double(frames.count))
        }

        return result
    }

    /// Upscales a single frame using Core Image Lanczos scaling.
    private func upscaleFrame(_ image: CGImage, scaleFactor: Int) throws -> CGImage {
        let ciImage = CIImage(cgImage: image)

        let scale = CGFloat(scaleFactor)
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = ciImage.transformed(by: transform)

        // Apply Lanczos scale filter for better quality
        guard let lanczosFilter = CIFilter(name: "CILanczosScaleTransform") else {
            // Fallback to simple transform if filter not available
            let extent = scaledImage.extent
            guard let cgImage = ciContext.createCGImage(scaledImage, from: extent) else {
                throw SuperResolutionError.processingFailed(nil)
            }
            return cgImage
        }

        lanczosFilter.setValue(ciImage, forKey: kCIInputImageKey)
        lanczosFilter.setValue(scale, forKey: kCIInputScaleKey)
        lanczosFilter.setValue(1.0, forKey: kCIInputAspectRatioKey)

        guard let outputImage = lanczosFilter.outputImage,
              let cgImage = ciContext.createCGImage(outputImage, from: outputImage.extent) else {
            throw SuperResolutionError.processingFailed(nil)
        }

        return cgImage
    }

    // MARK: - Pixel Buffer Helpers

    /// Creates an IOSurface-backed pixel buffer from a CGImage.
    private func createIOSurfaceBackedPixelBuffer(from image: CGImage) throws -> CVPixelBuffer {
        try createIOSurfaceBackedPixelBuffer(width: image.width, height: image.height, image: image)
    }

    /// Creates an IOSurface-backed pixel buffer with optional image content.
    private func createIOSurfaceBackedPixelBuffer(
        width: Int,
        height: Int,
        image: CGImage? = nil
    ) throws -> CVPixelBuffer {
        let attributes: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw SuperResolutionError.pixelBufferCreationFailed
        }

        // Draw image if provided
        if let image = image {
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

            guard let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) else {
                throw SuperResolutionError.pixelBufferCreationFailed
            }

            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        return buffer
    }

    /// Creates a CGImage from a CVPixelBuffer.
    private func createCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        return cgImage
    }
}
