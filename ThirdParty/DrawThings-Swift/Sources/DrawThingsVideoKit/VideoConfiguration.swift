//
//  VideoConfiguration.swift
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

/// Configuration for video assembly and processing.
///
/// This struct defines all the parameters needed for assembling frames into video,
/// including output settings, frame rate, interpolation, and codec options.
///
/// Example usage:
/// ```swift
/// let config = VideoConfiguration(
///     outputURL: outputURL,
///     frameRate: 24,
///     interpolation: .enabled(factor: 2)
/// )
/// ```
public struct VideoConfiguration: Sendable {
    /// The output URL for the assembled video.
    public var outputURL: URL

    /// The source frame rate of the input frames.
    /// Varies by model: Wan 2.1 = 16 fps, Wan 2.2 TI2V = 24 fps, LTX = 25 fps.
    public var sourceFrameRate: Int

    /// The target frame rate for the output video.
    /// When interpolation is disabled, the source frame rate is used instead.
    /// When interpolation is enabled, this is the desired output frame rate.
    public var frameRate: Int

    /// The video codec to use for encoding.
    public var codec: VideoCodec

    /// The quality preset for encoding.
    public var quality: VideoQuality

    /// Frame interpolation settings.
    public var interpolation: InterpolationMode

    /// Preferred interpolation method (nil = auto-select best available).
    public var interpolationMethod: InterpolationMethod?

    /// Interpolation pass mode (single-pass vs multi-pass for factors > 2).
    public var interpolationPassMode: InterpolationPassMode

    /// Super resolution settings.
    public var superResolution: SuperResolutionMode

    /// Preferred super resolution method (nil = auto-select best available).
    public var superResolutionMethod: SuperResolutionMethod?

    /// Whether to overwrite existing files at the output URL.
    public var overwriteExisting: Bool

    /// Optional audio track to include in the output.
    public var audioURL: URL?

    /// Optional audio data (WAV) to mux into the output video.
    /// Takes precedence over `audioURL` when both are set.
    public var audioData: Data?

    /// Creates a new video configuration.
    ///
    /// - Parameters:
    ///   - outputURL: The destination URL for the video file.
    ///   - sourceFrameRate: Source frame rate of input frames (default: 16, matching Draw Things output).
    ///   - frameRate: Target output frame rate when interpolation is enabled (default: 24).
    ///   - codec: Video codec to use (default: .h264).
    ///   - quality: Encoding quality preset (default: .high).
    ///   - interpolation: Frame interpolation mode (default: .disabled).
    ///   - interpolationMethod: Preferred interpolation method (default: nil for auto).
    ///   - interpolationPassMode: Single-pass or multi-pass interpolation (default: .singlePass).
    ///   - superResolution: Super resolution mode (default: .disabled).
    ///   - superResolutionMethod: Preferred super resolution method (default: nil for auto).
    ///   - overwriteExisting: Whether to overwrite existing files (default: true).
    ///   - audioURL: Optional audio track URL.
    ///   - audioData: Optional audio data (WAV) to mux into the output.
    public init(
        outputURL: URL,
        sourceFrameRate: Int = 16,
        frameRate: Int = 24,
        codec: VideoCodec = .h264,
        quality: VideoQuality = .high,
        interpolation: InterpolationMode = .disabled,
        interpolationMethod: InterpolationMethod? = nil,
        interpolationPassMode: InterpolationPassMode = .singlePass,
        superResolution: SuperResolutionMode = .disabled,
        superResolutionMethod: SuperResolutionMethod? = nil,
        overwriteExisting: Bool = true,
        audioURL: URL? = nil,
        audioData: Data? = nil
    ) {
        self.outputURL = outputURL
        self.sourceFrameRate = sourceFrameRate
        self.frameRate = frameRate
        self.codec = codec
        self.quality = quality
        self.interpolation = interpolation
        self.interpolationMethod = interpolationMethod
        self.interpolationPassMode = interpolationPassMode
        self.superResolution = superResolution
        self.superResolutionMethod = superResolutionMethod
        self.overwriteExisting = overwriteExisting
        self.audioURL = audioURL
        self.audioData = audioData
    }
}

// MARK: - Video Codec

/// Supported video codecs for encoding.
public enum VideoCodec: String, CaseIterable, Sendable {
    /// H.264/AVC - widely compatible, good compression.
    case h264

    /// H.265/HEVC - better compression, newer devices.
    case hevc

    /// ProRes 422 - high quality, larger files.
    case proRes422

    /// ProRes 4444 - highest quality with alpha support.
    case proRes4444

    /// The AVFoundation codec type.
    public var avCodecType: AVVideoCodecType {
        switch self {
        case .h264:
            return .h264
        case .hevc:
            return .hevc
        case .proRes422:
            return .proRes422
        case .proRes4444:
            return .proRes4444
        }
    }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .h264:
            return "H.264"
        case .hevc:
            return "HEVC (H.265)"
        case .proRes422:
            return "ProRes 422"
        case .proRes4444:
            return "ProRes 4444"
        }
    }
}

// MARK: - Video Quality

/// Quality presets for video encoding.
public enum VideoQuality: String, CaseIterable, Sendable {
    /// Low quality, smaller file size.
    case low

    /// Medium quality, balanced.
    case medium

    /// High quality, larger file size.
    case high

    /// Maximum quality, largest file size.
    case maximum

    /// The AVFoundation quality key value.
    public var avQualityValue: Float {
        switch self {
        case .low:
            return 0.25
        case .medium:
            return 0.5
        case .high:
            return 0.75
        case .maximum:
            return 1.0
        }
    }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        case .maximum:
            return "Maximum"
        }
    }
}

// MARK: - Interpolation Mode

/// Frame interpolation mode using VTFrameInterpolation.
public enum InterpolationMode: Sendable, Equatable {
    /// No frame interpolation.
    case disabled

    /// Enable frame interpolation with a multiplication factor.
    /// A factor of 2 doubles the frame count, 4 quadruples it, etc.
    case enabled(factor: Int)

    /// Whether interpolation is enabled.
    public var isEnabled: Bool {
        switch self {
        case .disabled:
            return false
        case .enabled:
            return true
        }
    }

    /// The interpolation factor (1 if disabled).
    public var factor: Int {
        switch self {
        case .disabled:
            return 1
        case .enabled(let factor):
            return max(1, factor)
        }
    }
}

// MARK: - Super Resolution Mode

/// Super resolution mode for upscaling video frames.
public enum SuperResolutionMode: Sendable, Equatable {
    /// No super resolution upscaling.
    case disabled

    /// Enable super resolution with a scale factor.
    /// A factor of 2 doubles the resolution (e.g., 512x512 -> 1024x1024).
    case enabled(factor: Int)

    /// Whether super resolution is enabled.
    public var isEnabled: Bool {
        switch self {
        case .disabled:
            return false
        case .enabled:
            return true
        }
    }

    /// The scale factor (1 if disabled).
    public var factor: Int {
        switch self {
        case .disabled:
            return 1
        case .enabled(let factor):
            return max(1, factor)
        }
    }
}
