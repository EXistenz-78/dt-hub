//
//  FrameInterpolator.swift
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

/// Errors that can occur during frame interpolation.
public enum FrameInterpolatorError: Error, LocalizedError, Sendable {
    case insufficientFrames
    case invalidFactor
    case configurationFailed(String)
    case processingFailed(Error?)
    case pixelBufferCreationFailed
    case unsupportedOnSimulator

    public var errorDescription: String? {
        switch self {
        case .insufficientFrames:
            return "At least 2 frames are required for interpolation"
        case .invalidFactor:
            return "Interpolation factor must be greater than 1"
        case .configurationFailed(let message):
            return "Frame processor configuration failed: \(message)"
        case .processingFailed(let error):
            return "Frame processing failed: \(error?.localizedDescription ?? "unknown error")"
        case .pixelBufferCreationFailed:
            return "Failed to create pixel buffer"
        case .unsupportedOnSimulator:
            return "VTFrameProcessor is not available on simulator"
        }
    }
}

/// Method used for frame interpolation.
public enum InterpolationMethod: String, Sendable {
    /// Apple's VTFrameProcessor ML-based interpolation (macOS 15.4+, iOS 26+).
    /// Provides high-quality motion-aware interpolation.
    case vtFrameProcessor

    /// Core Image dissolve transition (cross-fade).
    /// Available on all OS versions, lower quality but fast.
    case coreImageDissolve
}

/// Mode for applying interpolation at higher factors.
public enum InterpolationPassMode: String, Sendable, CaseIterable {
    /// Single-pass interpolation at the requested factor.
    /// Faster but may produce more artifacts with fast motion.
    case singlePass

    /// Multi-pass interpolation using cascaded 2x passes.
    /// For 4x: runs 2x → 2x. Slower but may reduce artifacts.
    case multiPass

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .singlePass:
            return "Single Pass"
        case .multiPass:
            return "Multi-Pass (2x→2x)"
        }
    }
}

/// Frame interpolator that uses VTFrameProcessor where available, with a Core Image fallback.
///
/// On macOS 15.4+ and iOS 26+, this uses Apple's ML-based VTFrameRateConversion for
/// motion-aware frame interpolation. Elsewhere, and in the simulator, it falls back to
/// Core Image dissolve transitions.
///
/// Example usage:
/// ```swift
/// let interpolator = FrameInterpolator()
/// let interpolatedFrames = try await interpolator.interpolate(
///     frames: originalFrames,
///     factor: 2
/// )
/// ```
public actor FrameInterpolator {
    /// Core Image context for fallback blending.
    private let ciContext: CIContext

    /// Force using a specific interpolation method (nil = auto-select best available).
    public var preferredMethod: InterpolationMethod?

    /// Creates a new frame interpolator.
    /// - Parameter preferredMethod: Optionally force a specific interpolation method.
    public init(preferredMethod: InterpolationMethod? = nil) {
        self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
        self.preferredMethod = preferredMethod
    }

    /// Returns the interpolation method that will be used.
    public var activeMethod: InterpolationMethod {
        if let preferred = preferredMethod {
            return preferred
        }

        if #available(macOS 15.4, iOS 26.0, *) {
            #if !targetEnvironment(simulator)
            if VTFrameRateConversionConfiguration.isSupported {
                return .vtFrameProcessor
            }
            #endif
        }

        return .coreImageDissolve
    }

    /// Checks if VTFrameProcessor-based interpolation is available.
    public static var isVTFrameProcessorAvailable: Bool {
        if #available(macOS 15.4, iOS 26.0, *) {
            #if !targetEnvironment(simulator)
            return VTFrameRateConversionConfiguration.isSupported
            #else
            return false
            #endif
        }
        return false
    }

    /// Interpolates frames to increase frame count.
    ///
    /// - Parameters:
    ///   - frames: Array of CGImages to interpolate between.
    ///   - factor: Multiplication factor (2 = double frames, 4 = quadruple, etc.).
    ///   - passMode: Single-pass or multi-pass interpolation (multi-pass applies to 4× only).
    ///   - progress: Optional progress callback (0.0 to 1.0).
    /// - Returns: Array of interpolated CGImages.
    /// - Throws: FrameInterpolatorError if interpolation fails.
    public func interpolate(
        frames: [CGImage],
        factor: Int,
        passMode: InterpolationPassMode = .singlePass,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [CGImage] {
        guard frames.count >= 2 else {
            throw FrameInterpolatorError.insufficientFrames
        }

        guard factor > 1 else {
            throw FrameInterpolatorError.invalidFactor
        }

        // Multi-pass mode: cascade 2x interpolations for factors > 2
        if passMode == .multiPass && factor > 2 {
            return try await interpolateMultiPass(
                frames: frames,
                factor: factor,
                progress: progress
            )
        }

        // Single-pass mode
        return try await interpolateSinglePass(
            frames: frames,
            factor: factor,
            progress: progress
        )
    }

    /// Performs multi-pass interpolation by cascading 2x passes.
    private func interpolateMultiPass(
        frames: [CGImage],
        factor: Int,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> [CGImage] {
        // Calculate number of 2x passes needed
        // factor 4 = 2 passes (2x → 2x)
        // factor 3 = not a power of 2, do 2x then trim or use single pass
        // For simplicity, we handle factor 4 as 2x→2x, factor 3 as 3x single pass

        if factor == 4 {
            // Two passes of 2x each
            // First pass: progress 0.0 - 0.5
            let firstPassFrames = try await interpolateSinglePass(
                frames: frames,
                factor: 2,
                progress: { p in progress?(p * 0.5) }
            )

            // Second pass: progress 0.5 - 1.0
            let secondPassFrames = try await interpolateSinglePass(
                frames: firstPassFrames,
                factor: 2,
                progress: { p in progress?(0.5 + p * 0.5) }
            )

            return secondPassFrames
        } else {
            // For non-power-of-2 factors, fall back to single pass
            return try await interpolateSinglePass(
                frames: frames,
                factor: factor,
                progress: progress
            )
        }
    }

    /// Performs single-pass interpolation at the specified factor.
    private func interpolateSinglePass(
        frames: [CGImage],
        factor: Int,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> [CGImage] {
        let method = activeMethod

        switch method {
        case .vtFrameProcessor:
            if #available(macOS 15.4, iOS 26.0, *) {
                #if !targetEnvironment(simulator)
                return try await interpolateWithVTFrameProcessor(
                    frames: frames,
                    factor: factor,
                    progress: progress
                )
                #else
                throw FrameInterpolatorError.unsupportedOnSimulator
                #endif
            } else {
                // Fallback if somehow we got here on older OS
                return try interpolateWithCoreImage(
                    frames: frames,
                    factor: factor,
                    progress: progress
                )
            }

        case .coreImageDissolve:
            return try interpolateWithCoreImage(
                frames: frames,
                factor: factor,
                progress: progress
            )
        }
    }

    // MARK: - VTFrameProcessor Implementation

    #if !targetEnvironment(simulator)
    @available(macOS 15.4, iOS 26.0, *)
    private func interpolateWithVTFrameProcessor(
        frames: [CGImage],
        factor: Int,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> [CGImage] {
        guard let firstFrame = frames.first else {
            throw FrameInterpolatorError.insufficientFrames
        }

        let width = firstFrame.width
        let height = firstFrame.height

        // Create configuration
        guard let configuration = VTFrameRateConversionConfiguration(
            frameWidth: width,
            frameHeight: height,
            usePrecomputedFlow: false,
            qualityPrioritization: .quality,
            revision: .revision1
        ) else {
            throw FrameInterpolatorError.configurationFailed("Failed to create VTFrameRateConversionConfiguration")
        }

        // Create processor and start session
        let processor = VTFrameProcessor()
        try processor.startSession(configuration: configuration)
        defer { processor.endSession() }

        var result: [CGImage] = []
        let totalPairs = frames.count - 1

        // Calculate interpolation phases (positions between frames)
        // For factor=2, we need 1 intermediate frame at 0.5
        // For factor=3, we need 2 intermediate frames at 0.33 and 0.67
        let intermediateCount = factor - 1
        let interpolationPhases: [Float] = (1...intermediateCount).map { i in
            Float(i) / Float(factor)
        }

        for pairIndex in 0..<totalPairs {
            // Add the source frame
            result.append(frames[pairIndex])

            // Create pixel buffers for source and next frame
            let sourceBuffer = try createIOSurfaceBackedPixelBuffer(from: frames[pairIndex])
            let nextBuffer = try createIOSurfaceBackedPixelBuffer(from: frames[pairIndex + 1])

            // Create destination buffers for interpolated frames
            var destinationBuffers: [CVPixelBuffer] = []
            for _ in 0..<intermediateCount {
                let destBuffer = try createIOSurfaceBackedPixelBuffer(width: width, height: height)
                destinationBuffers.append(destBuffer)
            }

            // Create VTFrameProcessorFrame objects
            let sourceTime = CMTime(value: CMTimeValue(pairIndex * 1000), timescale: 1000)
            let nextTime = CMTime(value: CMTimeValue((pairIndex + 1) * 1000), timescale: 1000)

            guard let sourceFrame = VTFrameProcessorFrame(buffer: sourceBuffer, presentationTimeStamp: sourceTime),
                  let nextFrame = VTFrameProcessorFrame(buffer: nextBuffer, presentationTimeStamp: nextTime) else {
                throw FrameInterpolatorError.pixelBufferCreationFailed
            }

            // Create destination frames
            var destinationFrames: [VTFrameProcessorFrame] = []
            for (i, destBuffer) in destinationBuffers.enumerated() {
                let phase = Float(i + 1) / Float(factor)
                let destTime = CMTime(
                    value: CMTimeValue(((Double(pairIndex) + Double(phase)) * 1000).rounded()),
                    timescale: 1000
                )
                guard let destFrame = VTFrameProcessorFrame(buffer: destBuffer, presentationTimeStamp: destTime) else {
                    throw FrameInterpolatorError.pixelBufferCreationFailed
                }
                destinationFrames.append(destFrame)
            }

            // Create parameters
            let submissionMode: VTFrameRateConversionParameters.SubmissionMode = pairIndex == 0 ? .random : .sequential

            guard let parameters = VTFrameRateConversionParameters(
                sourceFrame: sourceFrame,
                nextFrame: nextFrame,
                opticalFlow: nil,
                interpolationPhase: interpolationPhases,
                submissionMode: submissionMode,
                destinationFrames: destinationFrames
            ) else {
                throw FrameInterpolatorError.configurationFailed("Failed to create parameters")
            }

            // Process frames asynchronously
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                processor.process(parameters: parameters) { _, error in
                    if let error = error {
                        continuation.resume(throwing: FrameInterpolatorError.processingFailed(error))
                    } else {
                        continuation.resume()
                    }
                }
            }

            // Extract interpolated frames
            for destFrame in destinationFrames {
                if let cgImage = createCGImage(from: destFrame.buffer) {
                    result.append(cgImage)
                }
            }

            progress?(Double(pairIndex + 1) / Double(totalPairs))
        }

        // Add the last frame
        result.append(frames[frames.count - 1])

        return result
    }
    #endif

    // MARK: - Core Image Implementation (Fallback)

    private func interpolateWithCoreImage(
        frames: [CGImage],
        factor: Int,
        progress: (@Sendable (Double) -> Void)?
    ) throws -> [CGImage] {
        var result: [CGImage] = []
        let totalPairs = frames.count - 1
        let intermediateCount = factor - 1

        for pairIndex in 0..<totalPairs {
            result.append(frames[pairIndex])

            // Generate intermediate frames using dissolve
            let intermediateFrames = try generateBlendedFrames(
                from: frames[pairIndex],
                to: frames[pairIndex + 1],
                count: intermediateCount
            )
            result.append(contentsOf: intermediateFrames)

            progress?(Double(pairIndex + 1) / Double(totalPairs))
        }

        // Add the last frame
        result.append(frames[frames.count - 1])

        return result
    }

    /// Generates intermediate frames between two images using Core Image blending.
    private func generateBlendedFrames(
        from startFrame: CGImage,
        to endFrame: CGImage,
        count: Int
    ) throws -> [CGImage] {
        guard count > 0 else { return [] }

        let startImage = CIImage(cgImage: startFrame)
        let endImage = CIImage(cgImage: endFrame)

        var intermediateFrames: [CGImage] = []
        let extent = startImage.extent

        for i in 1...count {
            let fraction = CGFloat(i) / CGFloat(count + 1)

            guard let blendFilter = CIFilter(name: "CIDissolveTransition") else {
                throw FrameInterpolatorError.processingFailed(nil)
            }

            blendFilter.setValue(startImage, forKey: kCIInputImageKey)
            blendFilter.setValue(endImage, forKey: kCIInputTargetImageKey)
            blendFilter.setValue(fraction, forKey: kCIInputTimeKey)

            guard let outputImage = blendFilter.outputImage,
                  let cgImage = ciContext.createCGImage(outputImage, from: extent) else {
                throw FrameInterpolatorError.processingFailed(nil)
            }

            intermediateFrames.append(cgImage)
        }

        return intermediateFrames
    }

    // MARK: - Pixel Buffer Helpers

    /// Creates an IOSurface-backed pixel buffer from a CGImage (required for VTFrameProcessor).
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
            throw FrameInterpolatorError.pixelBufferCreationFailed
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
                throw FrameInterpolatorError.pixelBufferCreationFailed
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
