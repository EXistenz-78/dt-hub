//
//  DrawThingsConfiguration+FlatBuffer.swift
//  DrawThingsClient
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import FlatBuffers
import Foundation

extension DrawThingsConfiguration {
    // MARK: - Validation

    /// Checks that every value can be sent to a Draw Things server.
    ///
    /// - Throws: ``DrawThingsError/invalidConfiguration(field:reason:)`` naming the first bad field.
    public func validate() throws(DrawThingsError) {
        func fail(_ field: String, _ reason: String) -> DrawThingsError {
            .invalidConfiguration(field: field, reason: reason)
        }
        func size(_ field: String, _ value: Int32) throws(DrawThingsError) {
            guard value >= 64 else { throw fail(field, "must be at least 64 pixels (got \(value))") }
            guard value / 64 <= Int32(UInt16.max) else { throw fail(field, "is too large (\(value) pixels)") }
        }
        func nonNegative(_ field: String, _ value: Int32) throws(DrawThingsError) {
            guard value >= 0 else { throw fail(field, "must not be negative (got \(value))") }
        }
        func finite(_ field: String, _ value: Float) throws(DrawThingsError) {
            guard value.isFinite else { throw fail(field, "must be a finite number") }
        }
        func unitRange(_ field: String, _ value: Float) throws(DrawThingsError) {
            guard (0...1).contains(value) else { throw fail(field, "must be between 0 and 1 (got \(value))") }
        }

        try size("width", width)
        try size("height", height)
        guard steps >= 1 else { throw fail("steps", "must be at least 1 (got \(steps))") }
        guard batchCount >= 1 else { throw fail("batchCount", "must be at least 1 (got \(batchCount))") }
        guard (1...4).contains(batchSize) else { throw fail("batchSize", "must be between 1 and 4 (got \(batchSize))") }
        guard (0...Int32(UInt8.max)).contains(upscalerScaleFactor) else {
            throw fail("upscalerScaleFactor", "must be between 0 and 255 (got \(upscalerScaleFactor))")
        }
        try unitRange("strength", strength)
        try unitRange("hiresFixStrength", hiresFixStrength)
        try unitRange("refinerStart", refinerStart)

        for (field, value) in [
            ("clipSkip", clipSkip), ("imagePriorSteps", imagePriorSteps), ("numFrames", numFrames),
            ("fps", fps), ("motionScale", motionScale), ("stage2Steps", stage2Steps),
            ("originalImageWidth", originalImageWidth), ("originalImageHeight", originalImageHeight),
            ("targetImageWidth", targetImageWidth), ("targetImageHeight", targetImageHeight),
            ("negativeOriginalImageWidth", negativeOriginalImageWidth),
            ("negativeOriginalImageHeight", negativeOriginalImageHeight),
            ("diffusionTileOverlap", diffusionTileOverlap), ("decodingTileOverlap", decodingTileOverlap),
        ] {
            try nonNegative(field, value)
        }
        if hiresFix {
            try size("hiresFixWidth", hiresFixWidth)
            try size("hiresFixHeight", hiresFixHeight)
        } else {
            try nonNegative("hiresFixWidth", hiresFixWidth)
            try nonNegative("hiresFixHeight", hiresFixHeight)
        }
        if tiledDiffusion {
            try size("diffusionTileWidth", diffusionTileWidth)
            try size("diffusionTileHeight", diffusionTileHeight)
        }
        if tiledDecoding {
            try size("decodingTileWidth", decodingTileWidth)
            try size("decodingTileHeight", decodingTileHeight)
        }
        for (field, value) in [
            ("diffusionTileWidth", diffusionTileWidth), ("diffusionTileHeight", diffusionTileHeight),
            ("decodingTileWidth", decodingTileWidth), ("decodingTileHeight", decodingTileHeight),
        ] where value / 64 > Int32(UInt16.max) || value < 0 {
            throw fail(field, "is out of range (\(value) pixels)")
        }

        for (field, value) in [
            ("guidanceScale", guidanceScale), ("shift", shift), ("shiftForAudio", shiftForAudio),
            ("imageGuidanceScale", imageGuidanceScale), ("clipWeight", clipWeight), ("guidanceEmbed", guidanceEmbed),
            ("maskBlur", maskBlur), ("sharpness", sharpness), ("stochasticSamplingGamma", stochasticSamplingGamma),
            ("aestheticScore", aestheticScore), ("negativeAestheticScore", negativeAestheticScore),
            ("stage2Guidance", stage2Guidance), ("stage2Shift", stage2Shift), ("teaCacheThreshold", teaCacheThreshold),
            ("guidingFrameNoise", guidingFrameNoise), ("startFrameGuidance", startFrameGuidance),
            ("solAttentionTau", solAttentionTau), ("compressionArtifactsQuality", compressionArtifactsQuality),
        ] {
            try finite(field, value)
        }
        guard !model.isEmpty else { throw fail("model", "must not be empty") }

        for (index, lora) in loras.enumerated() {
            guard !lora.file.isEmpty else { throw fail("loras[\(index)].file", "must not be empty") }
            try finite("loras[\(index)].weight", lora.weight)
        }
        for (index, control) in controls.enumerated() {
            try finite("controls[\(index)].weight", control.weight)
            try finite("controls[\(index)].downSamplingRate", control.downSamplingRate)
            guard control.guidanceStart <= control.guidanceEnd else {
                throw fail("controls[\(index)]", "guidanceStart must not be after guidanceEnd")
            }
        }
    }

    // MARK: - FlatBuffer encoding

    /// Encodes the configuration as the FlatBuffer `GenerationConfiguration` the server expects.
    ///
    /// - Throws: ``DrawThingsError/invalidConfiguration(field:reason:)`` if ``validate()`` fails.
    public func toFlatBufferData() throws(DrawThingsError) -> Data {
        try validate()

        let configT = GenerationConfigurationT()
        // Validated above, so the narrowing conversions below cannot trap.
        func units(_ pixels: Int32) -> UInt16 { UInt16(pixels / 64) }

        configT.startWidth = units(width)
        configT.startHeight = units(height)

        // Core generation parameters
        configT.steps = UInt32(steps)
        configT.model = model
        configT.sampler = sampler
        configT.guidanceScale = guidanceScale
        configT.clipSkip = UInt32(clipSkip)
        configT.shift = shift
        configT.shiftForAudio = shiftForAudio
        configT.seed = seed ?? UInt32.random(in: .min ... .max)
        configT.seedMode = seedMode

        // Batch parameters
        configT.id = 0
        configT.batchCount = UInt32(batchCount)
        configT.batchSize = UInt32(batchSize)
        configT.strength = strength

        // Guidance parameters
        configT.imageGuidanceScale = imageGuidanceScale
        configT.clipWeight = clipWeight
        configT.guidanceEmbed = guidanceEmbed
        configT.speedUpWithGuidanceEmbed = speedUpWithGuidanceEmbed
        configT.cfgZeroStar = cfgZeroStar
        configT.cfgZeroInitSteps = cfgZeroInitSteps

        // Compression, color calibration and prompt expansion
        configT.compressionArtifacts = compressionArtifacts
        configT.compressionArtifactsQuality = compressionArtifactsQuality
        configT.colorCalibration = colorCalibration
        configT.expandPromptToJson = expandPromptToJson

        // Mask/Inpaint parameters
        configT.maskBlur = maskBlur
        configT.maskBlurOutset = maskBlurOutset
        configT.preserveOriginalAfterInpaint = preserveOriginalAfterInpaint

        // Quality parameters
        configT.sharpness = sharpness
        configT.stochasticSamplingGamma = stochasticSamplingGamma
        configT.aestheticScore = aestheticScore
        configT.negativeAestheticScore = negativeAestheticScore

        // Image prior parameters
        configT.negativePromptForImagePrior = negativePromptForImagePrior
        configT.imagePriorSteps = UInt32(imagePriorSteps)

        // Crop/Size parameters. Pass these through verbatim - do NOT substitute width/height
        // when they are 0. The Draw Things app sends 0 for an unset SDXL micro-conditioning
        // size and lets the server decide; substituting the start size here makes our
        // request differ from the UI's for an otherwise identical config.
        configT.cropTop = cropTop
        configT.cropLeft = cropLeft
        configT.originalImageHeight = UInt32(originalImageHeight)
        configT.originalImageWidth = UInt32(originalImageWidth)
        configT.targetImageHeight = UInt32(targetImageHeight)
        configT.targetImageWidth = UInt32(targetImageWidth)
        configT.negativeOriginalImageHeight = UInt32(negativeOriginalImageHeight)
        configT.negativeOriginalImageWidth = UInt32(negativeOriginalImageWidth)

        // Upscaler and face restoration
        configT.upscalerScaleFactor = UInt8(upscalerScaleFactor)
        configT.upscaler = upscaler?.isEmpty == false ? upscaler : nil
        configT.faceRestoration = faceRestoration?.isEmpty == false ? faceRestoration : nil

        // Text encoder parameters
        configT.resolutionDependentShift = resolutionDependentShift
        configT.t5TextEncoder = t5TextEncoder
        configT.separateClipL = separateClipL
        configT.separateOpenClipG = separateOpenClipG
        configT.separateT5 = separateT5
        configT.clipLText = clipLText
        configT.openClipGText = openClipGText
        configT.t5Text = t5Text

        // Tiled parameters
        configT.tiledDiffusion = tiledDiffusion
        configT.diffusionTileWidth = units(diffusionTileWidth)
        configT.diffusionTileHeight = units(diffusionTileHeight)
        configT.diffusionTileOverlap = units(diffusionTileOverlap)
        configT.tiledDecoding = tiledDecoding
        configT.decodingTileWidth = units(decodingTileWidth)
        configT.decodingTileHeight = units(decodingTileHeight)
        configT.decodingTileOverlap = units(decodingTileOverlap)

        // HiRes Fix parameters
        configT.hiresFix = hiresFix
        configT.hiresFixStartWidth = units(hiresFixWidth)
        configT.hiresFixStartHeight = units(hiresFixHeight)
        configT.hiresFixStrength = hiresFixStrength

        // Stage 2 parameters
        configT.stage2Steps = UInt32(stage2Steps)
        configT.stage2Cfg = stage2Guidance
        configT.stage2Shift = stage2Shift

        // TEA Cache and SOL attention
        configT.teaCache = teaCache
        configT.teaCacheStart = teaCacheStart
        configT.teaCacheEnd = teaCacheEnd
        configT.teaCacheThreshold = teaCacheThreshold
        configT.teaCacheMaxSkipSteps = teaCacheMaxSkipSteps
        configT.usesSolAttention = usesSolAttention
        configT.solAttentionStart = solAttentionStart
        configT.solAttentionTau = solAttentionTau
        configT.scheduler = scheduler
        configT.seamlessTile = seamlessTile

        // Causal inference parameters
        configT.causalInferenceEnabled = causalInferenceEnabled
        configT.causalInference = causalInference
        configT.causalInferencePad = causalInferencePad

        // Video parameters
        configT.fpsId = UInt32(fps)
        configT.motionBucketId = UInt32(motionScale)
        configT.condAug = guidingFrameNoise
        configT.startFrameCfg = startFrameGuidance
        configT.numFrames = UInt32(numFrames)

        // Refiner parameters
        configT.refinerModel = refinerModel?.isEmpty == false ? refinerModel : nil
        configT.refinerStart = refinerStart
        configT.zeroNegativePrompt = zeroNegativePrompt

        configT.name = name

        var controlsArray: [ControlT] = controls.map { control in
            let controlT = ControlT()
            controlT.file = control.file
            controlT.weight = control.weight
            controlT.guidanceStart = control.guidanceStart
            controlT.guidanceEnd = control.guidanceEnd
            controlT.controlMode = control.controlMode
            controlT.noPrompt = control.noPrompt
            controlT.globalAveragePooling = control.globalAveragePooling
            controlT.downSamplingRate = control.downSamplingRate
            controlT.inputOverride = control.inputOverride
            controlT.targetBlocks = control.targetBlocks
            return controlT
        }

        // The inpaint control enables mask-based inpainting; the mask itself is sent separately.
        if enableInpainting {
            let inpaintControl = ControlT()
            inpaintControl.inputOverride = .inpaint
            inpaintControl.weight = 1.0
            inpaintControl.guidanceStart = 0.0
            inpaintControl.guidanceEnd = 1.0
            inpaintControl.noPrompt = false
            inpaintControl.globalAveragePooling = true
            inpaintControl.downSamplingRate = 1.0
            inpaintControl.controlMode = .balanced
            inpaintControl.targetBlocks = []
            inpaintControl.file = ""
            controlsArray.append(inpaintControl)
        }
        configT.controls = controlsArray

        configT.loras = loras.map { lora in
            let loraT = LoRAT()
            loraT.file = lora.file
            loraT.weight = lora.weight
            loraT.mode = lora.mode
            return loraT
        }

        DTLogger.debug("FlatBuffer config: model=\(model), sampler=\(sampler), steps=\(steps), size=\(configT.startWidth * 64)x\(configT.startHeight * 64), guidance=\(guidanceScale), strength=\(strength), shift=\(shift), seed=\(configT.seed), seedMode=\(seedMode), controls=\(configT.controls.count), loras=\(configT.loras.count)", category: .configuration)

        // Match the upstream Draw Things app's serialization: default FlatBufferBuilder (no
        // serializeDefaults). Fields equal to the schema default are omitted from the wire
        // format; the server reader returns the same default for missing fields.
        var builder = FlatBufferBuilder(initialSize: 1024)
        var mutableConfigT = configT
        let offset = GenerationConfiguration.pack(&builder, obj: &mutableConfigT)
        builder.finish(offset: offset)
        return builder.data
    }
}
