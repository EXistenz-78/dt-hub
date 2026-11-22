//
//  GenerationProgress.swift
//  DrawThingsClient
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import Foundation

/// The pipeline stage a generation is in, as reported by the server.
public enum GenerationStage: Sendable, Hashable, CustomStringConvertible {
    case textEncoding
    case imageEncoding
    case sampling(step: Int)
    case imageDecoding
    case secondPassImageEncoding
    case secondPassSampling(step: Int)
    case secondPassImageDecoding
    case faceRestoration
    case imageUpscaling

    /// Maps a server signpost to a stage; nil for signposts the client doesn't know.
    init?(_ signpost: ImageGenerationSignpostProto) {
        switch signpost.signpost {
        case .textEncoded: self = .textEncoding
        case .imageEncoded: self = .imageEncoding
        case .sampling(let sampling): self = .sampling(step: Int(sampling.step))
        case .imageDecoded: self = .imageDecoding
        case .secondPassImageEncoded: self = .secondPassImageEncoding
        case .secondPassSampling(let sampling): self = .secondPassSampling(step: Int(sampling.step))
        case .secondPassImageDecoded: self = .secondPassImageDecoding
        case .faceRestored: self = .faceRestoration
        case .imageUpscaled: self = .imageUpscaling
        case nil: return nil
        }
    }

    public var description: String {
        switch self {
        case .textEncoding: return "Encoding text prompt..."
        case .imageEncoding: return "Encoding input image..."
        case .sampling(let step): return "Generating image (step \(step))..."
        case .imageDecoding: return "Decoding generated image..."
        case .secondPassImageEncoding: return "Preparing second pass..."
        case .secondPassSampling(let step): return "Second pass generation (step \(step))..."
        case .secondPassImageDecoding: return "Processing second pass..."
        case .faceRestoration: return "Restoring faces..."
        case .imageUpscaling: return "Upscaling image..."
        }
    }
}

/// A snapshot of generation progress. Each ``GenerationEvent/progress(_:)`` event carries a
/// new value; it is a value type, so assigning it to an observable property updates views.
public struct GenerationProgress: Sendable, Hashable {
    /// The current stage.
    public var stage: GenerationStage
    /// The sampling step within the current pass, when sampling (1-based as reported).
    public var step: Int?
    /// Configured sampling steps for the first pass.
    public var totalSteps: Int

    public init(stage: GenerationStage, step: Int? = nil, totalSteps: Int) {
        self.stage = stage
        self.step = step
        self.totalSteps = totalSteps
    }

    /// First-pass sampling progress from 0 to 1, or nil outside first-pass sampling.
    public var fractionCompleted: Double? {
        guard case .sampling(let step) = stage, totalSteps > 0 else { return nil }
        return min(1, max(0, Double(step) / Double(totalSteps)))
    }
}
