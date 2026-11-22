//
//  GenerationRequest.swift
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

/// Everything needed for one generation. A value type, so it can be queued, stored and sent
/// across tasks.
public struct GenerationRequest: Sendable, Identifiable {
    public var id: UUID
    public var prompt: String
    public var negativePrompt: String
    public var configuration: DrawThingsConfiguration
    /// Input image for image-to-image and inpainting. Its size should match the configuration's.
    public var image: CGImage?
    /// Inpainting mask: transparent pixels are regenerated, opaque pixels are kept.
    public var mask: CGImage?
    /// Control hints (depth, pose, moodboard...), built with ``HintBuilder``.
    public var hints: [HintProto]
    /// Explicit model metadata; when nil it is resolved by ``DrawThingsService/modelSpecs``.
    public var override: MetadataOverride?
    /// Overrides the model family detected from the model file name, which decides how
    /// previews are decoded and the video frame rate.
    public var modelFamily: ModelFamily?
    /// Overrides the audio sample rate derived from the model family.
    public var audioSampleRate: Double?

    public init(
        id: UUID = UUID(),
        prompt: String,
        negativePrompt: String = "",
        configuration: DrawThingsConfiguration = DrawThingsConfiguration(),
        image: CGImage? = nil,
        mask: CGImage? = nil,
        hints: [HintProto] = [],
        override: MetadataOverride? = nil,
        modelFamily: ModelFamily? = nil,
        audioSampleRate: Double? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.configuration = configuration
        self.image = image
        self.mask = mask
        self.hints = hints
        self.override = override
        self.modelFamily = modelFamily
        self.audioSampleRate = audioSampleRate
    }

    /// The media properties this request's output will have, from the model family. A result's
    /// ``GenerationResult/media`` also uses the model's spec, which can set a different frame rate.
    public var media: MediaProfile {
        MediaProfile(configuration: configuration, family: modelFamily, audioSampleRate: audioSampleRate)
    }
}

/// A request encoded for the wire: FlatBuffer configuration and input tensors.
struct PreparedGenerationInput: Sendable {
    let configuration: Data
    let image: Data?
    let mask: Data?

    /// Encodes the request's configuration and images. CPU-heavy for large images, so it runs
    /// on the caller's (non-actor) executor and checks for cancellation between steps.
    init(_ request: GenerationRequest) throws {
        try Task.checkCancellation()
        configuration = try request.configuration.toFlatBufferData()
        try Task.checkCancellation()
        image = try request.image.map { try ImageHelpers.imageToDTTensor($0, forceRGB: true) }
        try Task.checkCancellation()
        // Draw Things' mask is a 1-byte-per-pixel tensor derived from alpha, not an RGB tensor;
        // sending an RGB tensor crashes the server's inpainting check.
        mask = try request.mask.map { try ImageHelpers.createMaskFromAlpha($0) }
    }
}
