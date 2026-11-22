//
//  DrawThingsConfiguration+JSON.swift
//  DrawThingsClient
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import Foundation

// Draw Things' JSON configuration format (upstream `JSGenerationConfiguration`), as pasted into
// and copied from the app. Sizes are in pixels, enums are written the way the app writes them,
// and a negative seed means "random".
//
// The app produces two shapes of it:
// - "Copy Configuration" writes a compact subset: the settings relevant to the current model,
//   with "" for unset names. Pasting it only changes those settings, so it is an overlay.
// - Complete exports (such as GetConfigPro) write every key, with null for unset names.
//
// Encoding writes the complete shape, so the output reproduces the whole configuration when
// pasted into Draw Things. Decoding accepts both shapes and is lenient: missing keys take this
// type's defaults, and older spellings written by DrawThingsKit (integer LoRA modes,
// `controlMode`, "disabled" color calibration) are accepted. To apply a compact copy the way
// the app does, merge it onto a base configuration with ``DrawThingsConfiguration/mergeJSON(_:)``.

// MARK: - LoRAConfig

extension LoRAConfig: Codable {
    private enum CodingKeys: String, CodingKey { case file, weight, mode }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        file = try container.decodeIfPresent(String.self, forKey: .file) ?? ""
        weight = try container.decodeIfPresent(Float.self, forKey: .weight) ?? 1.0
        if let name = try? container.decodeIfPresent(String.self, forKey: .mode) {
            mode = LoRAMode(jsonName: name)
        } else if let raw = try? container.decodeIfPresent(Int8.self, forKey: .mode) {
            mode = LoRAMode(rawValue: raw) ?? .all
        } else {
            mode = .all
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(file, forKey: .file)
        try container.encode(weight, forKey: .weight)
        try container.encode(mode.jsonName, forKey: .mode)
    }
}

extension LoRAMode {
    var jsonName: String {
        switch self {
        case .all: return "all"
        case .base: return "base"
        case .refiner: return "refiner"
        }
    }

    init(jsonName: String) {
        switch jsonName.lowercased() {
        case "base": self = .base
        case "refiner": self = .refiner
        default: self = .all
        }
    }
}

// MARK: - ControlConfig

extension ControlConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case file, weight, guidanceStart, guidanceEnd, noPrompt, globalAveragePooling, downSamplingRate
        case controlImportance, inputOverride, targetBlocks
        case controlMode  // DrawThingsKit's older integer spelling of controlImportance
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ControlConfig(file: "")
        file = try container.decodeIfPresent(String.self, forKey: .file) ?? ""
        weight = try container.decodeIfPresent(Float.self, forKey: .weight) ?? defaults.weight
        guidanceStart = try container.decodeIfPresent(Float.self, forKey: .guidanceStart) ?? defaults.guidanceStart
        guidanceEnd = try container.decodeIfPresent(Float.self, forKey: .guidanceEnd) ?? defaults.guidanceEnd
        noPrompt = try container.decodeIfPresent(Bool.self, forKey: .noPrompt) ?? defaults.noPrompt
        globalAveragePooling = try container.decodeIfPresent(Bool.self, forKey: .globalAveragePooling) ?? defaults.globalAveragePooling
        downSamplingRate = try container.decodeIfPresent(Float.self, forKey: .downSamplingRate) ?? defaults.downSamplingRate
        targetBlocks = try container.decodeIfPresent([String].self, forKey: .targetBlocks) ?? []
        if let importance = try container.decodeIfPresent(String.self, forKey: .controlImportance) {
            controlMode = ControlMode(jsonName: importance)
        } else if let raw = try container.decodeIfPresent(Int8.self, forKey: .controlMode) {
            controlMode = ControlMode(rawValue: raw) ?? .balanced
        } else {
            controlMode = .balanced
        }
        inputOverride = ControlInputType(jsonName: try container.decodeIfPresent(String.self, forKey: .inputOverride) ?? "")
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(file, forKey: .file)
        try container.encode(weight, forKey: .weight)
        try container.encode(guidanceStart, forKey: .guidanceStart)
        try container.encode(guidanceEnd, forKey: .guidanceEnd)
        try container.encode(noPrompt, forKey: .noPrompt)
        try container.encode(globalAveragePooling, forKey: .globalAveragePooling)
        try container.encode(downSamplingRate, forKey: .downSamplingRate)
        try container.encode(controlMode.jsonName, forKey: .controlImportance)
        try container.encode(inputOverride.jsonName, forKey: .inputOverride)
        try container.encode(targetBlocks, forKey: .targetBlocks)
    }
}

extension ControlMode {
    var jsonName: String {
        switch self {
        case .balanced: return "balanced"
        case .prompt: return "prompt"
        case .control: return "control"
        }
    }

    init(jsonName: String) {
        switch jsonName.lowercased() {
        case "prompt": self = .prompt
        case "control": self = .control
        default: self = .balanced
        }
    }
}

extension ControlInputType {
    /// The lowercased case name, as the app writes it (`"depth"`, `"inpaint"`...).
    var jsonName: String { String(describing: self).lowercased() }

    init(jsonName: String) {
        let name = jsonName.lowercased()
        self = (Int8(0)...Int8(64)).lazy.compactMap(ControlInputType.init(rawValue:)).first { $0.jsonName == name } ?? .unspecified
    }
}

extension CompressionMethod {
    var jsonName: String {
        switch self {
        case .disabled: return "disabled"
        case .h264: return "h264"
        case .h265: return "h265"
        case .jpeg: return "jpeg"
        }
    }

    init(jsonName: String) {
        switch jsonName.lowercased() {
        case "h264": self = .h264
        case "h265": self = .h265
        case "jpeg": self = .jpeg
        default: self = .disabled
        }
    }
}

extension ColorCalibration {
    // Current app versions write "none"; older exports wrote "disabled". Both decode as disabled.
    var jsonName: String { self == .lab ? "lab" : "none" }

    init(jsonName: String) {
        self = jsonName.lowercased() == "lab" ? .lab : .disabled
    }
}

// MARK: - DrawThingsConfiguration

extension DrawThingsConfiguration: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, width, height, seed, steps, guidanceScale, strength, model, sampler
        case hiresFix, hiresFixWidth, hiresFixHeight, hiresFixStrength
        case tiledDecoding, decodingTileWidth, decodingTileHeight, decodingTileOverlap
        case tiledDiffusion, diffusionTileWidth, diffusionTileHeight, diffusionTileOverlap
        case upscaler, upscalerScaleFactor, imageGuidanceScale, seedMode, clipSkip, controls, loras
        case maskBlur, maskBlurOutset, sharpness, faceRestoration, clipWeight
        case negativePromptForImagePrior, imagePriorSteps, refinerModel
        case originalImageHeight, originalImageWidth, cropTop, cropLeft, targetImageHeight, targetImageWidth
        case aestheticScore, negativeAestheticScore, zeroNegativePrompt, refinerStart
        case negativeOriginalImageHeight, negativeOriginalImageWidth
        case batchCount, batchSize, numFrames, fps, motionScale, guidingFrameNoise, startFrameGuidance
        case shift, shiftForAudio, usesSolAttention, solAttentionStart, solAttentionTau
        case stage2Steps, stage2Guidance, stage2Shift, stochasticSamplingGamma, preserveOriginalAfterInpaint
        case t5TextEncoder, separateClipL, clipLText, separateOpenClipG, openClipGText
        case speedUpWithGuidanceEmbed, guidanceEmbed, resolutionDependentShift
        case teaCache, teaCacheStart, teaCacheEnd, teaCacheThreshold, teaCacheMaxSkipSteps
        case separateT5, t5Text, causalInference, causalInferencePad, cfgZeroStar, cfgZeroInitSteps
        case compressionArtifacts, compressionArtifactsQuality, colorCalibration, expandPromptToJson
        // DrawThingsClient additions (ignored by the Draw Things app)
        case name, enableInpainting
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var config = DrawThingsConfiguration()

        func read<T: Decodable>(_ key: CodingKeys, into value: inout T) throws {
            if let decoded = try c.decodeIfPresent(T.self, forKey: key) { value = decoded }
        }
        /// Optional strings: an empty string means "none", as in the app.
        func readName(_ key: CodingKeys) throws -> String? {
            guard let value = try c.decodeIfPresent(String.self, forKey: key), !value.isEmpty else { return nil }
            return value
        }

        try read(.width, into: &config.width)
        try read(.height, into: &config.height)
        if let seed = try c.decodeIfPresent(Int64.self, forKey: .seed) {
            config.seed = (0...Int64(UInt32.max)).contains(seed) ? UInt32(seed) : nil
        }
        try read(.steps, into: &config.steps)
        try read(.guidanceScale, into: &config.guidanceScale)
        try read(.strength, into: &config.strength)
        try read(.model, into: &config.model)
        if let raw = try c.decodeIfPresent(Int8.self, forKey: .sampler) {
            guard let sampler = SamplerType(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(forKey: .sampler, in: c, debugDescription: "Unknown sampler \(raw)")
            }
            config.sampler = sampler
        }
        try read(.hiresFix, into: &config.hiresFix)
        try read(.hiresFixWidth, into: &config.hiresFixWidth)
        try read(.hiresFixHeight, into: &config.hiresFixHeight)
        try read(.hiresFixStrength, into: &config.hiresFixStrength)
        try read(.tiledDecoding, into: &config.tiledDecoding)
        try read(.decodingTileWidth, into: &config.decodingTileWidth)
        try read(.decodingTileHeight, into: &config.decodingTileHeight)
        try read(.decodingTileOverlap, into: &config.decodingTileOverlap)
        try read(.tiledDiffusion, into: &config.tiledDiffusion)
        try read(.diffusionTileWidth, into: &config.diffusionTileWidth)
        try read(.diffusionTileHeight, into: &config.diffusionTileHeight)
        try read(.diffusionTileOverlap, into: &config.diffusionTileOverlap)
        config.upscaler = try readName(.upscaler)
        try read(.upscalerScaleFactor, into: &config.upscalerScaleFactor)
        try read(.imageGuidanceScale, into: &config.imageGuidanceScale)
        if let raw = try c.decodeIfPresent(Int8.self, forKey: .seedMode) {
            guard let seedMode = SeedMode(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(forKey: .seedMode, in: c, debugDescription: "Unknown seed mode \(raw)")
            }
            config.seedMode = seedMode
        }
        try read(.clipSkip, into: &config.clipSkip)
        try read(.controls, into: &config.controls)
        try read(.loras, into: &config.loras)
        try read(.maskBlur, into: &config.maskBlur)
        try read(.maskBlurOutset, into: &config.maskBlurOutset)
        try read(.sharpness, into: &config.sharpness)
        config.faceRestoration = try readName(.faceRestoration)
        try read(.clipWeight, into: &config.clipWeight)
        try read(.negativePromptForImagePrior, into: &config.negativePromptForImagePrior)
        try read(.imagePriorSteps, into: &config.imagePriorSteps)
        config.refinerModel = try readName(.refinerModel)
        try read(.originalImageHeight, into: &config.originalImageHeight)
        try read(.originalImageWidth, into: &config.originalImageWidth)
        try read(.cropTop, into: &config.cropTop)
        try read(.cropLeft, into: &config.cropLeft)
        try read(.targetImageHeight, into: &config.targetImageHeight)
        try read(.targetImageWidth, into: &config.targetImageWidth)
        try read(.aestheticScore, into: &config.aestheticScore)
        try read(.negativeAestheticScore, into: &config.negativeAestheticScore)
        try read(.zeroNegativePrompt, into: &config.zeroNegativePrompt)
        try read(.refinerStart, into: &config.refinerStart)
        try read(.negativeOriginalImageHeight, into: &config.negativeOriginalImageHeight)
        try read(.negativeOriginalImageWidth, into: &config.negativeOriginalImageWidth)
        try read(.batchCount, into: &config.batchCount)
        try read(.batchSize, into: &config.batchSize)
        try read(.numFrames, into: &config.numFrames)
        try read(.fps, into: &config.fps)
        try read(.motionScale, into: &config.motionScale)
        try read(.guidingFrameNoise, into: &config.guidingFrameNoise)
        try read(.startFrameGuidance, into: &config.startFrameGuidance)
        try read(.shift, into: &config.shift)
        try read(.shiftForAudio, into: &config.shiftForAudio)
        try read(.usesSolAttention, into: &config.usesSolAttention)
        try read(.solAttentionStart, into: &config.solAttentionStart)
        try read(.solAttentionTau, into: &config.solAttentionTau)
        try read(.stage2Steps, into: &config.stage2Steps)
        try read(.stage2Guidance, into: &config.stage2Guidance)
        try read(.stage2Shift, into: &config.stage2Shift)
        try read(.stochasticSamplingGamma, into: &config.stochasticSamplingGamma)
        try read(.preserveOriginalAfterInpaint, into: &config.preserveOriginalAfterInpaint)
        try read(.t5TextEncoder, into: &config.t5TextEncoder)
        try read(.separateClipL, into: &config.separateClipL)
        config.clipLText = try readName(.clipLText)
        try read(.separateOpenClipG, into: &config.separateOpenClipG)
        config.openClipGText = try readName(.openClipGText)
        try read(.speedUpWithGuidanceEmbed, into: &config.speedUpWithGuidanceEmbed)
        try read(.guidanceEmbed, into: &config.guidanceEmbed)
        try read(.resolutionDependentShift, into: &config.resolutionDependentShift)
        try read(.teaCache, into: &config.teaCache)
        try read(.teaCacheStart, into: &config.teaCacheStart)
        try read(.teaCacheEnd, into: &config.teaCacheEnd)
        try read(.teaCacheThreshold, into: &config.teaCacheThreshold)
        try read(.teaCacheMaxSkipSteps, into: &config.teaCacheMaxSkipSteps)
        try read(.separateT5, into: &config.separateT5)
        config.t5Text = try readName(.t5Text)
        // The app writes 0 when causal inference is off.
        if let causalInference = try c.decodeIfPresent(Int32.self, forKey: .causalInference) {
            config.causalInferenceEnabled = causalInference > 0
            if causalInference > 0 { config.causalInference = causalInference }
        }
        try read(.causalInferencePad, into: &config.causalInferencePad)
        try read(.cfgZeroStar, into: &config.cfgZeroStar)
        try read(.cfgZeroInitSteps, into: &config.cfgZeroInitSteps)
        if let name = try c.decodeIfPresent(String.self, forKey: .compressionArtifacts) {
            config.compressionArtifacts = CompressionMethod(jsonName: name)
        }
        try read(.compressionArtifactsQuality, into: &config.compressionArtifactsQuality)
        if let name = try c.decodeIfPresent(String.self, forKey: .colorCalibration) {
            config.colorCalibration = ColorCalibration(jsonName: name)
        }
        try read(.expandPromptToJson, into: &config.expandPromptToJson)
        config.name = try readName(.name)
        try read(.enableInpainting, into: &config.enableInpainting)

        self = config
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Int64(0), forKey: .id)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encode(seed.map(Int64.init) ?? -1, forKey: .seed)
        try c.encode(steps, forKey: .steps)
        try c.encode(guidanceScale, forKey: .guidanceScale)
        try c.encode(strength, forKey: .strength)
        try c.encode(model, forKey: .model)
        try c.encode(sampler.rawValue, forKey: .sampler)
        try c.encode(hiresFix, forKey: .hiresFix)
        try c.encode(hiresFixWidth, forKey: .hiresFixWidth)
        try c.encode(hiresFixHeight, forKey: .hiresFixHeight)
        try c.encode(hiresFixStrength, forKey: .hiresFixStrength)
        try c.encode(tiledDecoding, forKey: .tiledDecoding)
        try c.encode(decodingTileWidth, forKey: .decodingTileWidth)
        try c.encode(decodingTileHeight, forKey: .decodingTileHeight)
        try c.encode(decodingTileOverlap, forKey: .decodingTileOverlap)
        try c.encode(tiledDiffusion, forKey: .tiledDiffusion)
        try c.encode(diffusionTileWidth, forKey: .diffusionTileWidth)
        try c.encode(diffusionTileHeight, forKey: .diffusionTileHeight)
        try c.encode(diffusionTileOverlap, forKey: .diffusionTileOverlap)
        try c.encode(upscaler, forKey: .upscaler)
        try c.encode(upscalerScaleFactor, forKey: .upscalerScaleFactor)
        try c.encode(imageGuidanceScale, forKey: .imageGuidanceScale)
        try c.encode(seedMode.rawValue, forKey: .seedMode)
        try c.encode(clipSkip, forKey: .clipSkip)
        try c.encode(controls, forKey: .controls)
        try c.encode(loras, forKey: .loras)
        try c.encode(maskBlur, forKey: .maskBlur)
        try c.encode(maskBlurOutset, forKey: .maskBlurOutset)
        try c.encode(sharpness, forKey: .sharpness)
        try c.encode(faceRestoration, forKey: .faceRestoration)
        try c.encode(clipWeight, forKey: .clipWeight)
        try c.encode(negativePromptForImagePrior, forKey: .negativePromptForImagePrior)
        try c.encode(imagePriorSteps, forKey: .imagePriorSteps)
        try c.encode(refinerModel, forKey: .refinerModel)
        try c.encode(originalImageHeight, forKey: .originalImageHeight)
        try c.encode(originalImageWidth, forKey: .originalImageWidth)
        try c.encode(cropTop, forKey: .cropTop)
        try c.encode(cropLeft, forKey: .cropLeft)
        try c.encode(targetImageHeight, forKey: .targetImageHeight)
        try c.encode(targetImageWidth, forKey: .targetImageWidth)
        try c.encode(aestheticScore, forKey: .aestheticScore)
        try c.encode(negativeAestheticScore, forKey: .negativeAestheticScore)
        try c.encode(zeroNegativePrompt, forKey: .zeroNegativePrompt)
        try c.encode(refinerStart, forKey: .refinerStart)
        try c.encode(negativeOriginalImageHeight, forKey: .negativeOriginalImageHeight)
        try c.encode(negativeOriginalImageWidth, forKey: .negativeOriginalImageWidth)
        try c.encode(batchCount, forKey: .batchCount)
        try c.encode(batchSize, forKey: .batchSize)
        try c.encode(numFrames, forKey: .numFrames)
        try c.encode(fps, forKey: .fps)
        try c.encode(motionScale, forKey: .motionScale)
        try c.encode(guidingFrameNoise, forKey: .guidingFrameNoise)
        try c.encode(startFrameGuidance, forKey: .startFrameGuidance)
        try c.encode(shift, forKey: .shift)
        try c.encode(shiftForAudio, forKey: .shiftForAudio)
        try c.encode(usesSolAttention, forKey: .usesSolAttention)
        try c.encode(solAttentionStart, forKey: .solAttentionStart)
        try c.encode(solAttentionTau, forKey: .solAttentionTau)
        try c.encode(stage2Steps, forKey: .stage2Steps)
        try c.encode(stage2Guidance, forKey: .stage2Guidance)
        try c.encode(stage2Shift, forKey: .stage2Shift)
        try c.encode(stochasticSamplingGamma, forKey: .stochasticSamplingGamma)
        try c.encode(preserveOriginalAfterInpaint, forKey: .preserveOriginalAfterInpaint)
        try c.encode(t5TextEncoder, forKey: .t5TextEncoder)
        try c.encode(separateClipL, forKey: .separateClipL)
        try c.encode(clipLText, forKey: .clipLText)
        try c.encode(separateOpenClipG, forKey: .separateOpenClipG)
        try c.encode(openClipGText, forKey: .openClipGText)
        try c.encode(speedUpWithGuidanceEmbed, forKey: .speedUpWithGuidanceEmbed)
        try c.encode(guidanceEmbed, forKey: .guidanceEmbed)
        try c.encode(resolutionDependentShift, forKey: .resolutionDependentShift)
        try c.encode(teaCache, forKey: .teaCache)
        try c.encode(teaCacheStart, forKey: .teaCacheStart)
        try c.encode(teaCacheEnd, forKey: .teaCacheEnd)
        try c.encode(teaCacheThreshold, forKey: .teaCacheThreshold)
        try c.encode(teaCacheMaxSkipSteps, forKey: .teaCacheMaxSkipSteps)
        try c.encode(separateT5, forKey: .separateT5)
        try c.encodeIfPresent(t5Text, forKey: .t5Text)
        try c.encode(causalInferenceEnabled ? causalInference : 0, forKey: .causalInference)
        try c.encode(causalInferenceEnabled ? causalInferencePad : 0, forKey: .causalInferencePad)
        try c.encode(cfgZeroStar, forKey: .cfgZeroStar)
        try c.encode(cfgZeroInitSteps, forKey: .cfgZeroInitSteps)
        try c.encode(compressionArtifacts.jsonName, forKey: .compressionArtifacts)
        try c.encode(compressionArtifactsQuality, forKey: .compressionArtifactsQuality)
        try c.encode(colorCalibration.jsonName, forKey: .colorCalibration)
        try c.encode(expandPromptToJson, forKey: .expandPromptToJson)
        try c.encodeIfPresent(name, forKey: .name)
        if enableInpainting { try c.encode(true, forKey: .enableInpainting) }
    }
}

// MARK: - JSON strings

extension DrawThingsConfiguration {
    /// The configuration as Draw Things JSON (pretty-printed, sorted keys), which can be pasted
    /// into the Draw Things app.
    ///
    /// - Parameter includeSeed: When false, the seed is written as -1 (random).
    public func toJSON(includeSeed: Bool = true) throws -> String {
        var configuration = self
        if !includeSeed { configuration.seed = nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(configuration), as: UTF8.self)
    }

    /// Parses Draw Things JSON, either a complete export or the app's compact "Copy
    /// Configuration". Missing keys take their default values; to apply a compact copy on top of
    /// existing settings, as pasting into the app does, use ``mergeJSON(_:)`` instead.
    public static func fromJSON(_ json: String) throws -> DrawThingsConfiguration {
        try JSONDecoder().decode(DrawThingsConfiguration.self, from: Data(json.utf8))
    }

    /// Applies the keys present in `json` on top of this configuration; other values are kept.
    /// An empty string or `{}` changes nothing.
    public mutating func mergeJSON(_ json: String) throws {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "{}" else { return }
        guard let overlay = try JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any] else {
            throw DrawThingsError.decodingFailed("configuration JSON must be an object")
        }
        guard var merged = try JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) as? [String: Any] else {
            throw DrawThingsError.decodingFailed("could not encode the current configuration")
        }
        merged.merge(overlay) { _, new in new }
        self = try JSONDecoder().decode(DrawThingsConfiguration.self, from: JSONSerialization.data(withJSONObject: merged))
    }

    /// The result of ``validateJSON(_:)``.
    public struct ValidationResult: Sendable {
        /// Whether the JSON parsed as a configuration that passes ``validate()``.
        public let isValid: Bool
        /// A readable description of the problem, when invalid.
        public let error: String?
        /// The parsed configuration, when valid.
        public let configuration: DrawThingsConfiguration?

        public static func success(_ configuration: DrawThingsConfiguration) -> ValidationResult {
            ValidationResult(isValid: true, error: nil, configuration: configuration)
        }

        public static func failure(_ error: String) -> ValidationResult {
            ValidationResult(isValid: false, error: error, configuration: nil)
        }
    }

    /// Parses and validates Draw Things JSON, describing the first problem found. An empty
    /// string or `{}` is valid and yields the default configuration.
    public static func validateJSON(_ json: String) -> ValidationResult {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "{}" {
            return .success(DrawThingsConfiguration())
        }
        guard (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil else {
            return .failure("Invalid JSON syntax")
        }
        let configuration: DrawThingsConfiguration
        do {
            configuration = try fromJSON(trimmed)
        } catch let error as DecodingError {
            switch error {
            case .typeMismatch(let type, let context):
                return .failure("Type mismatch for '\(context.codingPath.map(\.stringValue).joined(separator: "."))': expected \(type)")
            case .valueNotFound(let type, let context):
                return .failure("Missing value for '\(context.codingPath.map(\.stringValue).joined(separator: "."))': expected \(type)")
            case .dataCorrupted(let context):
                return .failure(context.debugDescription)
            case .keyNotFound(let key, _):
                return .failure("Missing required key: \(key.stringValue)")
            @unknown default:
                return .failure(error.localizedDescription)
            }
        } catch {
            return .failure(error.localizedDescription)
        }
        do {
            try configuration.validate()
        } catch {
            return .failure(error.localizedDescription)
        }
        return .success(configuration)
    }

    /// Pretty-prints a JSON string with sorted keys, or returns nil if it isn't valid JSON.
    public static func formatJSON(_ json: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
