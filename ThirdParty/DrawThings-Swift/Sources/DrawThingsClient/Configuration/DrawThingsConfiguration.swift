//
//  DrawThingsConfiguration.swift
//  DrawThingsClient
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import Foundation

/// A LoRA applied to the generation.
public struct LoRAConfig: Sendable, Hashable {
    public var file: String
    public var weight: Float
    public var mode: LoRAMode

    public init(file: String, weight: Float = 1.0, mode: LoRAMode = .all) {
        self.file = file
        self.weight = weight
        self.mode = mode
    }
}

/// A control (ControlNet, T2I adapter, IP adapter...) applied to the generation.
public struct ControlConfig: Sendable, Hashable {
    public var file: String
    public var weight: Float
    public var guidanceStart: Float
    public var guidanceEnd: Float
    public var controlMode: ControlMode
    /// Matches the per-model value the app looks up in its ControlNet zoo. False
    /// for every stock control except Shuffle, which needs true.
    public var globalAveragePooling: Bool
    public var noPrompt: Bool
    public var downSamplingRate: Float
    /// Overrides the hint type the control consumes (`.unspecified` uses the model's own).
    public var inputOverride: ControlInputType
    public var targetBlocks: [String]

    public init(
        file: String,
        weight: Float = 1.0,
        guidanceStart: Float = 0.0,
        guidanceEnd: Float = 1.0,
        controlMode: ControlMode = .balanced,
        globalAveragePooling: Bool = false,
        noPrompt: Bool = false,
        downSamplingRate: Float = 1.0,
        inputOverride: ControlInputType = .unspecified,
        targetBlocks: [String] = []
    ) {
        self.file = file
        self.weight = weight
        self.guidanceStart = guidanceStart
        self.guidanceEnd = guidanceEnd
        self.controlMode = controlMode
        self.globalAveragePooling = globalAveragePooling
        self.noPrompt = noPrompt
        self.downSamplingRate = downSamplingRate
        self.inputOverride = inputOverride
        self.targetBlocks = targetBlocks
    }
}

/// Generation settings, mirroring the Draw Things app's configuration.
///
/// Sizes are in pixels and are sent in units of 64 (rounded down), as Draw Things requires.
/// ``validate()`` reports values the server can't accept; ``toFlatBufferData()`` calls it.
/// The configuration is `Codable` in Draw Things' own JSON format (the format of the app's
/// "Copy Configuration"), see ``toJSON(includeSeed:)`` and ``fromJSON(_:)``.
///
/// The defaults are Draw Things' own preset for Z Image Turbo (`z_image_turbo_1.0_q8p.ckpt`,
/// 1024×1024, 8 steps, UniPC Trailing, guidance 1, shift 3, no resolution-dependent shift),
/// a model most servers have. Sampler, steps, guidance and shift depend on the model: when you
/// change `model`, set them for that model too, ideally from the app's Copy Configuration.
public struct DrawThingsConfiguration: Sendable, Hashable {
    // Core parameters (sizes are sent in units of 64 pixels, rounded down)
    public var width: Int32
    public var height: Int32
    public var steps: Int32
    public var model: String
    public var sampler: SamplerType
    public var guidanceScale: Float
    /// The seed, or nil for a random seed each generation.
    public var seed: UInt32?
    public var clipSkip: Int32
    public var loras: [LoRAConfig]
    public var controls: [ControlConfig]
    public var shift: Float
    /// Shift for the audio stream of audio-video models (LTX-2, MiniMax H3).
    public var shiftForAudio: Float

    // Batch parameters
    public var batchCount: Int32
    public var batchSize: Int32
    public var strength: Float

    // Guidance parameters
    public var imageGuidanceScale: Float
    public var clipWeight: Float
    public var guidanceEmbed: Float
    public var speedUpWithGuidanceEmbed: Bool
    public var cfgZeroStar: Bool
    public var cfgZeroInitSteps: Int32

    // Compression parameters
    public var compressionArtifacts: CompressionMethod
    public var compressionArtifactsQuality: Float

    // Color calibration
    public var colorCalibration: ColorCalibration

    // Prompt expansion
    public var expandPromptToJson: Bool

    // Mask/Inpaint parameters
    public var maskBlur: Float
    public var maskBlurOutset: Int32
    public var preserveOriginalAfterInpaint: Bool
    public var enableInpainting: Bool  // When true, adds inpaint control to enable mask-based inpainting

    // Quality parameters
    public var sharpness: Float
    public var stochasticSamplingGamma: Float
    public var aestheticScore: Float
    public var negativeAestheticScore: Float

    // Image prior parameters
    public var negativePromptForImagePrior: Bool
    public var imagePriorSteps: Int32

    // Crop/Size parameters
    public var cropTop: Int32
    public var cropLeft: Int32
    public var originalImageHeight: Int32
    public var originalImageWidth: Int32
    public var targetImageHeight: Int32
    public var targetImageWidth: Int32
    public var negativeOriginalImageHeight: Int32
    public var negativeOriginalImageWidth: Int32

    // Upscaler parameters
    public var upscalerScaleFactor: Int32

    // Text encoder parameters
    public var resolutionDependentShift: Bool
    public var t5TextEncoder: Bool
    public var separateClipL: Bool
    public var separateOpenClipG: Bool
    public var separateT5: Bool

    // Tiled parameters
    public var tiledDiffusion: Bool
    public var diffusionTileWidth: Int32
    public var diffusionTileHeight: Int32
    public var diffusionTileOverlap: Int32
    public var tiledDecoding: Bool
    public var decodingTileWidth: Int32
    public var decodingTileHeight: Int32
    public var decodingTileOverlap: Int32

    // HiRes Fix parameters (sizes are sent in units of 64 pixels, rounded down)
    public var hiresFix: Bool
    public var hiresFixWidth: Int32
    public var hiresFixHeight: Int32
    public var hiresFixStrength: Float

    // Stage 2 parameters
    public var stage2Steps: Int32
    public var stage2Guidance: Float
    public var stage2Shift: Float

    // TEA Cache parameters
    public var teaCache: Bool
    public var teaCacheStart: Int32
    public var teaCacheEnd: Int32
    public var teaCacheThreshold: Float
    public var teaCacheMaxSkipSteps: Int32

    // SOL attention (sparse attention for video models)
    public var usesSolAttention: Bool
    public var solAttentionStart: Int32
    public var solAttentionTau: Float
    /// Atelier-fork field: 0 is the sampler's own scheduler, then simple, sgm_uniform, normal, karras,
    /// exponential, linear_quadratic, beta. Servers without the field ignore it.
    public var scheduler: Int32
    /// Atelier-fork field: the custom server tiles the picture seamlessly when it is not 0 (1 left-right, 2 up-down,
    /// 3 both). 0 is off and is never written to the wire. Servers without the field ignore it.
    public var seamlessTile: Int8

    // Causal inference parameters
    public var causalInferenceEnabled: Bool
    public var causalInference: Int32
    public var causalInferencePad: Int32

    // Video parameters
    public var fps: Int32
    public var motionScale: Int32
    public var guidingFrameNoise: Float
    public var startFrameGuidance: Float
    public var numFrames: Int32

    // Refiner parameters
    public var refinerModel: String?
    public var refinerStart: Float
    public var zeroNegativePrompt: Bool

    // Upscaler parameters
    public var upscaler: String?

    // Face restoration
    public var faceRestoration: String?

    // Configuration name
    public var name: String?

    // Separate text encoder prompts
    public var clipLText: String?
    public var openClipGText: String?
    public var t5Text: String?

    public var seedMode: SeedMode

    public init(
        width: Int32 = 1024,
        height: Int32 = 1024,
        steps: Int32 = 8,
        model: String = "z_image_turbo_1.0_q8p.ckpt",
        sampler: SamplerType = .unipctrailing,
        guidanceScale: Float = 1.0,
        seed: UInt32? = nil,
        clipSkip: Int32 = 1,
        loras: [LoRAConfig] = [],
        controls: [ControlConfig] = [],
        shift: Float = 3.0,
        shiftForAudio: Float = 3.0,
        batchCount: Int32 = 1,
        batchSize: Int32 = 1,
        strength: Float = 1.0,
        imageGuidanceScale: Float = 1.5,
        clipWeight: Float = 1.0,
        guidanceEmbed: Float = 3.5,
        speedUpWithGuidanceEmbed: Bool = true,
        cfgZeroStar: Bool = false,
        cfgZeroInitSteps: Int32 = 0,
        compressionArtifacts: CompressionMethod = .disabled,
        compressionArtifactsQuality: Float = 43.1,
        colorCalibration: ColorCalibration = .disabled,
        expandPromptToJson: Bool = false,
        maskBlur: Float = 1.5,
        maskBlurOutset: Int32 = 0,
        preserveOriginalAfterInpaint: Bool = true,
        enableInpainting: Bool = false,
        sharpness: Float = 0.0,
        stochasticSamplingGamma: Float = 0.3,
        aestheticScore: Float = 6.0,
        negativeAestheticScore: Float = 2.5,
        negativePromptForImagePrior: Bool = true,
        imagePriorSteps: Int32 = 5,
        cropTop: Int32 = 0,
        cropLeft: Int32 = 0,
        originalImageHeight: Int32 = 0,
        originalImageWidth: Int32 = 0,
        targetImageHeight: Int32 = 0,
        targetImageWidth: Int32 = 0,
        negativeOriginalImageHeight: Int32 = 0,
        negativeOriginalImageWidth: Int32 = 0,
        upscalerScaleFactor: Int32 = 0,
        resolutionDependentShift: Bool = false,
        t5TextEncoder: Bool = true,
        separateClipL: Bool = false,
        separateOpenClipG: Bool = false,
        separateT5: Bool = false,
        tiledDiffusion: Bool = false,
        diffusionTileWidth: Int32 = 1024,
        diffusionTileHeight: Int32 = 1024,
        diffusionTileOverlap: Int32 = 128,
        tiledDecoding: Bool = false,
        decodingTileWidth: Int32 = 640,
        decodingTileHeight: Int32 = 640,
        decodingTileOverlap: Int32 = 128,
        hiresFix: Bool = false,
        hiresFixWidth: Int32 = 0,
        hiresFixHeight: Int32 = 0,
        hiresFixStrength: Float = 0.7,
        stage2Steps: Int32 = 10,
        stage2Guidance: Float = 1.0,
        stage2Shift: Float = 1.0,
        teaCache: Bool = false,
        teaCacheStart: Int32 = 5,
        teaCacheEnd: Int32 = -1,
        teaCacheThreshold: Float = 0.06,
        teaCacheMaxSkipSteps: Int32 = 3,
        usesSolAttention: Bool = false,
        solAttentionStart: Int32 = 2,
        solAttentionTau: Float = 0.5,
        scheduler: Int32 = 0,
        seamlessTile: Int8 = 0,
        causalInferenceEnabled: Bool = false,
        causalInference: Int32 = 3,
        causalInferencePad: Int32 = 0,
        fps: Int32 = 5,
        motionScale: Int32 = 127,
        guidingFrameNoise: Float = 0.02,
        startFrameGuidance: Float = 1.0,
        numFrames: Int32 = 14,
        refinerModel: String? = nil,
        refinerStart: Float = 0.85,
        zeroNegativePrompt: Bool = false,
        upscaler: String? = nil,
        faceRestoration: String? = nil,
        name: String? = nil,
        clipLText: String? = nil,
        openClipGText: String? = nil,
        t5Text: String? = nil,
        seedMode: SeedMode = .scalealike
    ) {
        self.width = width
        self.height = height
        self.steps = steps
        self.model = model
        self.sampler = sampler
        self.guidanceScale = guidanceScale
        self.seed = seed
        self.clipSkip = clipSkip
        self.loras = loras
        self.controls = controls
        self.shift = shift
        self.shiftForAudio = shiftForAudio
        self.batchCount = batchCount
        self.batchSize = batchSize
        self.strength = strength
        self.imageGuidanceScale = imageGuidanceScale
        self.clipWeight = clipWeight
        self.guidanceEmbed = guidanceEmbed
        self.speedUpWithGuidanceEmbed = speedUpWithGuidanceEmbed
        self.cfgZeroStar = cfgZeroStar
        self.cfgZeroInitSteps = cfgZeroInitSteps
        self.compressionArtifacts = compressionArtifacts
        self.compressionArtifactsQuality = compressionArtifactsQuality
        self.colorCalibration = colorCalibration
        self.expandPromptToJson = expandPromptToJson
        self.maskBlur = maskBlur
        self.maskBlurOutset = maskBlurOutset
        self.preserveOriginalAfterInpaint = preserveOriginalAfterInpaint
        self.enableInpainting = enableInpainting
        self.sharpness = sharpness
        self.stochasticSamplingGamma = stochasticSamplingGamma
        self.aestheticScore = aestheticScore
        self.negativeAestheticScore = negativeAestheticScore
        self.negativePromptForImagePrior = negativePromptForImagePrior
        self.imagePriorSteps = imagePriorSteps
        self.cropTop = cropTop
        self.cropLeft = cropLeft
        self.originalImageHeight = originalImageHeight
        self.originalImageWidth = originalImageWidth
        self.targetImageHeight = targetImageHeight
        self.targetImageWidth = targetImageWidth
        self.negativeOriginalImageHeight = negativeOriginalImageHeight
        self.negativeOriginalImageWidth = negativeOriginalImageWidth
        self.upscalerScaleFactor = upscalerScaleFactor
        self.resolutionDependentShift = resolutionDependentShift
        self.t5TextEncoder = t5TextEncoder
        self.separateClipL = separateClipL
        self.separateOpenClipG = separateOpenClipG
        self.separateT5 = separateT5
        self.tiledDiffusion = tiledDiffusion
        self.diffusionTileWidth = diffusionTileWidth
        self.diffusionTileHeight = diffusionTileHeight
        self.diffusionTileOverlap = diffusionTileOverlap
        self.tiledDecoding = tiledDecoding
        self.decodingTileWidth = decodingTileWidth
        self.decodingTileHeight = decodingTileHeight
        self.decodingTileOverlap = decodingTileOverlap
        self.hiresFix = hiresFix
        self.hiresFixWidth = hiresFixWidth
        self.hiresFixHeight = hiresFixHeight
        self.hiresFixStrength = hiresFixStrength
        self.stage2Steps = stage2Steps
        self.stage2Guidance = stage2Guidance
        self.stage2Shift = stage2Shift
        self.teaCache = teaCache
        self.teaCacheStart = teaCacheStart
        self.teaCacheEnd = teaCacheEnd
        self.teaCacheThreshold = teaCacheThreshold
        self.teaCacheMaxSkipSteps = teaCacheMaxSkipSteps
        self.usesSolAttention = usesSolAttention
        self.solAttentionStart = solAttentionStart
        self.solAttentionTau = solAttentionTau
        self.scheduler = scheduler
        self.seamlessTile = seamlessTile
        self.causalInferenceEnabled = causalInferenceEnabled
        self.causalInference = causalInference
        self.causalInferencePad = causalInferencePad
        self.fps = fps
        self.motionScale = motionScale
        self.guidingFrameNoise = guidingFrameNoise
        self.startFrameGuidance = startFrameGuidance
        self.numFrames = numFrames
        self.refinerModel = refinerModel
        self.refinerStart = refinerStart
        self.zeroNegativePrompt = zeroNegativePrompt
        self.upscaler = upscaler
        self.faceRestoration = faceRestoration
        self.name = name
        self.clipLText = clipLText
        self.openClipGText = openClipGText
        self.t5Text = t5Text
        self.seedMode = seedMode
    }
}
