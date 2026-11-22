//
//  ModelFamily.swift
//  DrawThingsClient
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import Foundation

/// Model architecture families.
///
/// The family decides how latent previews are converted to RGB (each architecture has its own
/// latent space), plus media properties of video models such as frame rate and audio sample rate.
/// Detect it from a model file name or version string with ``detect(from:)``.
public enum ModelFamily: String, Sendable, CaseIterable {
    /// Stable Diffusion 1.x, 2.x (4-channel latent)
    case sd1
    /// Stable Diffusion XL (4-channel latent)
    case sdxl
    /// Stable Diffusion 3 (16-channel latent)
    case sd3
    /// Flux.1 models (16-channel latent)
    case flux
    /// HunyuanVideo (16-channel latent)
    case hunyuanVideo
    /// Qwen Image Edit (16-channel latent, same coefficients as Wan 2.1)
    case qwen
    /// Qwen Image 2.1 (64-channel latent; final images are RGBA from its transparent decoder)
    case qwen21
    /// Z Image (16-channel latent, uses Flux-like coefficients)
    case zImage
    /// Wan 2.1 models (16-channel latent)
    case wan21
    /// Wan 2.2 5B model (48-channel latent)
    case wan22
    /// Flux 2 models (32-channel latent)
    case flux2
    /// LTX-2 models (16-channel latent, TAESD-only preview)
    case ltx2
    /// LTX-2.3 models (16-channel latent, TAESD-only preview)
    case ltx23
    /// HiDream-O1 (patch-packed latent: 3 × 32 × 32 channels, patch-based preview decode)
    case hiDreamO1
    /// Kandinsky 2.1 (4-channel latent, OKLab color space)
    case kandinsky
    /// Würstchen / Stable Cascade Stage B/C (3- or 4-channel latent)
    case wurstchen
    /// MiniMax H3 (24-channel video latent with audio latent rows packed below)
    case minimaxH3
    /// LongCat-Video Avatar 1.5 (16-channel latent, same coefficients as Wan 2.1, 25 fps)
    case longcatVideoAvatar
    /// Unknown model - will use default coefficients
    case unknown

    /// Detect model family from model filename or version string.
    ///
    /// - Parameter modelNameOrVersion: The model filename (e.g., "flux1-dev-q8p.gguf") or version string (e.g., "qwenImage", "flux1")
    /// - Returns: The detected model family
    public static func detect(from modelNameOrVersion: String) -> ModelFamily {
        let lowercased = modelNameOrVersion.lowercased()

        // First check for exact version identifiers from Draw Things (case-insensitive).
        // These come from CheckpointModel.version and mirror the upstream ModelVersion enum
        // (matched both as lowercased Swift case names and as raw string values).
        // Each entry routes to the ModelFamily whose coefficients upstream uses for it.
        switch lowercased {
        case "qwenimage", "qwen_image":
            return .qwen
        case "qwenimage2_1", "qwen_image_2.1":
            return .qwen21
        case "cosmos2_5_2b", "cosmos2.5_2b":
            // Cosmos 2.5 shares the Wan 2.1 / Qwen 16-channel coefficients upstream.
            return .qwen
        case "zimage", "z_image":
            return .zImage
        case "flux2", "flux2_9b", "flux2_4b":
            return .flux2
        case "ernieimage", "ernie_image":
            // Ernie Image uses the 32-channel Flux 2 coefficients upstream.
            return .flux2
        case "ideogram4", "ideogram_4":
            // Ideogram 4 uses the 32-channel Flux 2 coefficients upstream.
            return .flux2
        case "krea2", "krea_2":
            // Krea 2 uses the 16-channel Qwen/Wan 2.1 coefficients upstream.
            return .qwen
        case "ltx2":
            return .ltx2
        case "ltx2_3", "ltx2.3":
            return .ltx23
        case "flux1", "hidreami1", "hidream_i1":
            return .flux
        case "seedvr2_3b", "seedvr2_7b":
            // SeedVR2 uses the 16-channel Flux coefficients upstream.
            return .flux
        case "hidreamo1", "hidream_o1":
            return .hiDreamO1
        case "wan21_1_3b", "wan21_14b", "wan_v2.1_1.3b", "wan_v2.1_14b":
            return .wan21
        case "wan22_5b", "wan_v2.2_5b":
            return .wan22
        case "minimaxh3", "minimax_h3":
            return .minimaxH3
        case "longcatvideoavatar1_5", "longcat_video_avatar_v1.5":
            // LongCat-Video Avatar shares the Wan 2.1 16-channel coefficients upstream.
            return .longcatVideoAvatar
        case "hunyuanvideo", "hunyuan_video":
            return .hunyuanVideo
        case "sd3", "sd3large", "sd3_large":
            return .sd3
        case "sdxlbase", "sdxlrefiner", "ssd1b", "sdxl_base_v0.9", "sdxl_refiner_v0.9", "ssd_1b":
            return .sdxl
        case "pixart", "auraflow":
            // Pixart / AuraFlow use the 4-channel SDXL coefficients upstream.
            return .sdxl
        case "kandinsky21", "kandinsky2.1":
            return .kandinsky
        case "wurstchenstagec", "wurstchenstageb", "wurstchen_v3.0_stage_c", "wurstchen_v3.0_stage_b":
            return .wurstchen
        case "svdi2v", "svd_i2v", "v1", "v2":
            // v1 / v2 / SVD share the distinct 4-channel coefficients upstream.
            return .sd1
        default:
            break
        }

        // Fall back to substring matching for filenames
        if lowercased.contains("flux2") {
            return .flux2
        }
        // HiDream-O1 must be checked before the generic hidream -> .flux rule.
        if lowercased.contains("hidreamo1") || lowercased.contains("hidream_o1") || lowercased.contains("hidream-o1") || (lowercased.contains("hidream") && lowercased.contains("o1")) {
            return .hiDreamO1
        }
        if lowercased.contains("ltx2.3") || lowercased.contains("ltx-2.3") || lowercased.contains("ltx_2.3") || lowercased.contains("ltx_2_3") || lowercased.contains("ltx23") {
            return .ltx23
        }
        if lowercased.contains("ltx2") || lowercased.contains("ltx-2") || lowercased.contains("ltx_2") {
            return .ltx2
        }
        if lowercased.contains("ideogram") {
            return .flux2
        }
        if lowercased.contains("ernie") {
            return .flux2
        }
        if lowercased.contains("krea") {
            return .qwen
        }
        if lowercased.contains("seedvr") {
            return .flux
        }
        if lowercased.contains("flux") || lowercased.contains("hidream") {
            return .flux
        }
        if lowercased.contains("zimage") || lowercased.contains("z_image") || lowercased.contains("z-image") {
            return .zImage
        }
        if lowercased.contains("qwen") {
            // Qwen Image 2.1 has its own 64-channel latent; don't match 2512 / 2511 / Qwen 2.5 VL.
            if lowercased.contains("2.1") || lowercased.contains("2_1") || lowercased.contains("2-1")
                || lowercased.contains("image21") || lowercased.contains("image_21") {
                return .qwen21
            }
            return .qwen
        }
        if lowercased.contains("cosmos") {
            return .qwen
        }
        if lowercased.contains("minimax") {
            return .minimaxH3
        }
        if lowercased.contains("longcat") {
            return .longcatVideoAvatar
        }
        if lowercased.contains("wan") {
            // Distinguish Wan 2.2 (5B) from Wan 2.1
            if lowercased.contains("wan22") || lowercased.contains("wan_2.2") || lowercased.contains("wan-2.2") || lowercased.contains("5b") {
                return .wan22
            }
            return .wan21
        }
        if lowercased.contains("hunyuan") && lowercased.contains("video") {
            return .hunyuanVideo
        }
        if lowercased.contains("kandinsky") {
            return .kandinsky
        }
        if lowercased.contains("wurstchen") || lowercased.contains("cascade") {
            return .wurstchen
        }
        if lowercased.contains("sd3") || lowercased.contains("sd_3") || lowercased.contains("stable-diffusion-3") {
            return .sd3
        }
        if lowercased.contains("sdxl") || lowercased.contains("sd_xl") || lowercased.contains("xl_base") || lowercased.contains("xl_refiner") || lowercased.contains("pixart") || lowercased.contains("auraflow") {
            return .sdxl
        }
        // SVD shares the v1/v2 4-channel coefficients; check before the generic sd_ rule.
        if lowercased.contains("svd") {
            return .sd1
        }
        if lowercased.contains("sd_") || lowercased.contains("v1-") || lowercased.contains("v2-") {
            return .sd1
        }

        // Default to unknown for unrecognized models
        return .unknown
    }

    /// The number of latent channels for this model family.
    ///
    /// For `.hiDreamO1` this is the patch-packed channel count (3 × 32 × 32 = 3072),
    /// not a conventional latent channel count — its preview uses a patch-based decode.
    public var latentChannels: Int {
        switch self {
        case .sd1, .sdxl, .kandinsky, .wurstchen:
            return 4
        case .sd3, .flux, .hunyuanVideo, .qwen, .zImage, .wan21, .ltx2, .ltx23, .longcatVideoAvatar:
            return 16
        case .minimaxH3:
            return 24
        case .flux2:
            return 32
        case .wan22:
            return 48
        case .qwen21:
            return 64
        case .hiDreamO1:
            return 3 * 32 * 32
        case .unknown:
            return 16  // Default assumption for unknown
        }
    }

    /// The usual frame rate for video model families, or `nil` for image-only models. A model's
    /// spec can set its own rate (see ``ModelSpec/framesPerSecond``), which takes precedence.
    /// Matches Draw Things' `ModelZoo.framesPerSecondForModel`.
    public var nativeFrameRate: Int? {
        switch self {
        case .wan21:
            return 16
        case .wan22, .minimaxH3:
            return 24
        case .ltx2, .ltx23, .longcatVideoAvatar:
            return 25
        case .hunyuanVideo:
            return 30
        default:
            return nil
        }
    }

    /// The frame rate for a video model version string (as in a model spec), or `nil` for image
    /// models. Covers Stable Video Diffusion, which decodes with the ``sd1`` family.
    /// Matches Draw Things' `ModelZoo.framesPerSecondForModel`.
    public static func frameRate(forVersion version: String) -> Int? {
        switch version.lowercased() {
        case "svdi2v", "svd_i2v":
            return 30
        default:
            let family = detect(from: version)
            return family == .unknown ? nil : family.nativeFrameRate
        }
    }

    /// The sample rate of audio generated by this family, or `nil` for families that don't
    /// generate audio. Generated audio carries no rate metadata, so it must come from the model.
    /// Matches Draw Things' `ModelZoo.audioSampleRateForModel`.
    public var audioSampleRate: Double? {
        switch self {
        case .minimaxH3: return 32_000
        case .longcatVideoAvatar: return 16_000
        case .ltx2: return 24_000
        case .ltx23: return 48_000
        default: return nil
        }
    }

    /// The sample rate assumed for audio from a model with no known rate.
    public static let defaultAudioSampleRate: Double = 24_000
}

@available(*, deprecated, renamed: "ModelFamily")
public typealias LatentModelFamily = ModelFamily
