//
//  ResponseAssembler.swift
//  DrawThingsClient
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import Foundation

/// Reassembles chunked image and audio tensors from a stream of `ImageGenerationResponse`s.
///
/// With `chunked = true` the server sends each result tensor in its own message and splits
/// tensors larger than 4 MiB across several messages: every chunk but the last is marked
/// `.moreChunks`. This mirrors the upstream `RemoteImageGenerator` reassembly.
struct ResponseAssembler: Sendable {
    /// Tensors completed by one response message.
    struct Output: Sendable, Equatable {
        var images: [Data] = []
        var audio: [Data] = []
    }

    private var pendingImage = Data()
    private var pendingAudio = Data()

    /// Feeds one response and returns any tensors it completed.
    mutating func consume(_ response: ImageGenerationResponse) -> Output {
        var output = Output()
        if !response.generatedImages.isEmpty {
            output.images = Self.assemble(response.generatedImages, state: response.chunkState, pending: &pendingImage)
        }
        if !response.generatedAudio.isEmpty {
            output.audio = Self.assemble(response.generatedAudio, state: response.chunkState, pending: &pendingAudio)
        }
        return output
    }

    /// True when a chunked tensor was started but its last chunk never arrived.
    var hasIncompleteTensor: Bool { !pendingImage.isEmpty || !pendingAudio.isEmpty }

    private static func assemble(_ parts: [Data], state: ChunkState, pending: inout Data) -> [Data] {
        switch state {
        case .lastChunk:
            var tensors = parts
            if !pending.isEmpty {
                tensors[0] = pending + tensors[0]
                pending = Data()
            }
            return tensors
        case .moreChunks:
            if let first = parts.first { pending.append(first) }
            return []
        case .UNRECOGNIZED:
            return []
        }
    }
}
