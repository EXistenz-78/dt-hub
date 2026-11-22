//
//  GenerationResult.swift
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

/// The output of a completed generation.
public struct GenerationResult: Sendable, Identifiable {
    /// The request's ID.
    public var id: UUID { request.id }
    /// The request that produced this result.
    public let request: GenerationRequest
    /// Generated images; for video models, the frames in order.
    public let images: [CGImage]
    /// Generated audio tracks (video models with sound).
    public let audio: [GeneratedAudio]
    /// Media properties: whether this is a video, its frame rate and audio sample rate.
    public let media: MediaProfile
    public let startedAt: Date
    public let completedAt: Date

    public init(
        request: GenerationRequest,
        images: [CGImage],
        audio: [GeneratedAudio],
        media: MediaProfile,
        startedAt: Date,
        completedAt: Date
    ) {
        self.request = request
        self.images = images
        self.audio = audio
        self.media = media
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    public var duration: TimeInterval { completedAt.timeIntervalSince(startedAt) }

    /// The images as `NSImage` / `UIImage`.
    public var platformImages: [PlatformImage] { images.map(PlatformImage.fromCGImage) }
}
