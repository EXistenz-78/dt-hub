//
//  ConfigurationPresets.swift
//  DrawThingsKit
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import Foundation
import DrawThingsClient

// MARK: - Dimension Presets

/// A preset dimension configuration.
public struct DimensionPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let width: Int
    public let height: Int

    public init(name: String, width: Int, height: Int) {
        self.id = "\(name)-\(width)x\(height)"
        self.name = name
        self.width = width
        self.height = height
    }
}

/// Standard dimension presets for image generation.
public enum DimensionPresets {
    /// Square formats
    public static let square512 = DimensionPreset(name: "Square 512", width: 512, height: 512)
    public static let square768 = DimensionPreset(name: "Square 768", width: 768, height: 768)
    public static let square1024 = DimensionPreset(name: "Square 1024", width: 1024, height: 1024)

    /// Portrait formats
    public static let portrait768x1024 = DimensionPreset(name: "Portrait 3:4", width: 768, height: 1024)
    public static let portrait832x1216 = DimensionPreset(name: "Portrait 2:3", width: 832, height: 1216)
    public static let portrait896x1152 = DimensionPreset(name: "Portrait 7:9", width: 896, height: 1152)

    /// Landscape formats
    public static let landscape1024x768 = DimensionPreset(name: "Landscape 4:3", width: 1024, height: 768)
    public static let landscape1216x832 = DimensionPreset(name: "Landscape 3:2", width: 1216, height: 832)
    public static let landscape1152x896 = DimensionPreset(name: "Landscape 9:7", width: 1152, height: 896)

    /// Widescreen formats
    public static let hd1280x720 = DimensionPreset(name: "HD 720p", width: 1280, height: 720)
    public static let fullHD1920x1080 = DimensionPreset(name: "Full HD 1080p", width: 1920, height: 1080)
    public static let ultrawide1344x768 = DimensionPreset(name: "Ultrawide 16:9", width: 1344, height: 768)

    /// All presets in a convenient array.
    public static let all: [DimensionPreset] = [
        square512, square768, square1024,
        portrait768x1024, portrait832x1216, portrait896x1152,
        landscape1024x768, landscape1216x832, landscape1152x896,
        hd1280x720, fullHD1920x1080, ultrawide1344x768
    ]

    /// Common presets for quick access.
    public static let common: [DimensionPreset] = [
        square1024, portrait768x1024, landscape1024x768, hd1280x720
    ]
}

// MARK: - Sampler Information

/// Display information for a sampler type.
public struct SamplerInfo: Identifiable, Hashable, Sendable {
    public let id: Int
    public let type: SamplerType
    public let name: String
    public let shortName: String

    public init(type: SamplerType, name: String, shortName: String) {
        self.id = Int(type.rawValue)
        self.type = type
        self.name = name
        self.shortName = shortName
    }
}

/// Sampler type information and utilities.
public enum SamplerPresets {
    /// All available samplers with display names.
    public static let all: [SamplerInfo] = [
        SamplerInfo(type: .dpmpp2mkarras, name: "DPM++ 2M Karras", shortName: "DPM++ 2M K"),
        SamplerInfo(type: .eulera, name: "Euler Ancestral", shortName: "Euler A"),
        SamplerInfo(type: .ddim, name: "DDIM", shortName: "DDIM"),
        SamplerInfo(type: .plms, name: "PLMS", shortName: "PLMS"),
        SamplerInfo(type: .dpmppsdekarras, name: "DPM++ SDE Karras", shortName: "DPM++ SDE K"),
        SamplerInfo(type: .unipc, name: "UniPC", shortName: "UniPC"),
        SamplerInfo(type: .lcm, name: "LCM", shortName: "LCM"),
        SamplerInfo(type: .eulerasubstep, name: "Euler A Substep", shortName: "Euler A Sub"),
        SamplerInfo(type: .dpmppsdesubstep, name: "DPM++ SDE Substep", shortName: "DPM++ SDE Sub"),
        SamplerInfo(type: .tcd, name: "TCD", shortName: "TCD"),
        SamplerInfo(type: .euleratrailing, name: "Euler A Trailing", shortName: "Euler A Trail"),
        SamplerInfo(type: .dpmppsdetrailing, name: "DPM++ SDE Trailing", shortName: "DPM++ SDE Trail"),
        SamplerInfo(type: .dpmpp2mays, name: "DPM++ 2M AYS", shortName: "DPM++ 2M AYS"),
        SamplerInfo(type: .euleraays, name: "Euler A AYS", shortName: "Euler A AYS"),
        SamplerInfo(type: .dpmppsdeays, name: "DPM++ SDE AYS", shortName: "DPM++ SDE AYS"),
        SamplerInfo(type: .dpmpp2mtrailing, name: "DPM++ 2M Trailing", shortName: "DPM++ 2M Trail"),
        SamplerInfo(type: .ddimtrailing, name: "DDIM Trailing", shortName: "DDIM Trail"),
        SamplerInfo(type: .unipctrailing, name: "UniPC Trailing", shortName: "UniPC Trail"),
        SamplerInfo(type: .unipcays, name: "UniPC AYS", shortName: "UniPC AYS"),
        SamplerInfo(type: .tcdtrailing, name: "TCD Trailing", shortName: "TCD Trail"),
    ]

    /// Commonly used samplers.
    public static let common: [SamplerInfo] = [
        all[0],  // DPM++ 2M Karras
        all[1],  // Euler A
        all[2],  // DDIM
        all[4],  // DPM++ SDE Karras
        all[5],  // UniPC
        all[6],  // LCM
    ]

    /// Get display name for a sampler type.
    public static func name(for sampler: SamplerType) -> String {
        all.first { $0.type == sampler }?.name ?? "Unknown"
    }

    /// Get sampler info by type.
    public static func info(for sampler: SamplerType) -> SamplerInfo? {
        all.first { $0.type == sampler }
    }
}

// MARK: - Control Mode Utilities

extension ControlMode {
    /// Display name for the control mode.
    public var displayName: String {
        switch self {
        case .balanced: return "Balanced"
        case .prompt: return "Prompt"
        case .control: return "Control"
        }
    }
}

// MARK: - LoRA Mode Utilities

extension LoRAMode {
    /// Display name for the LoRA mode.
    public var displayName: String {
        switch self {
        case .all: return "All"
        case .base: return "Base"
        case .refiner: return "Refiner"
        }
    }
}

// MARK: - Configuration Defaults

/// Default values for configuration parameters, matching `DrawThingsConfiguration()`: Draw Things'
/// preset for Z Image Turbo. Sampler, steps, guidance and shift suit that model only.
public enum ConfigurationDefaults {
    // Core
    public static let model = "z_image_turbo_1.0_q8p.ckpt"
    public static let width: Int32 = 1024
    public static let height: Int32 = 1024
    public static let steps: Int32 = 8
    public static let guidanceScale: Float = 1.0
    public static let sampler: SamplerType = .unipctrailing

    // Sampling
    public static let clipSkip: Int32 = 1
    public static let shift: Float = 3.0
    public static let resolutionDependentShift = false
    public static let strength: Float = 1.0

    // Batch
    public static let batchCount: Int32 = 1
    public static let batchSize: Int32 = 1

    // Guidance
    public static let imageGuidanceScale: Float = 1.5
    public static let clipWeight: Float = 1.0
    public static let guidanceEmbed: Float = 3.5

    // Quality
    public static let sharpness: Float = 0.0
    public static let aestheticScore: Float = 6.0
    public static let negativeAestheticScore: Float = 2.5

    // Mask
    public static let maskBlur: Float = 1.5
    public static let maskBlurOutset: Int32 = 0

    // Video
    public static let fps: Int32 = 5
    public static let numFrames: Int32 = 14
    public static let motionScale: Int32 = 127

    // HiRes Fix
    public static let hiresFixStrength: Float = 0.7

    // Refiner
    public static let refinerStart: Float = 0.85
}
