//
//  GenerationEvent.swift
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

/// An event from ``DrawThingsService/stream(_:)``, delivered in the order the server sent it.
/// The last event of a successful generation is always ``completed(_:)``.
public enum GenerationEvent: Sendable {
    /// The server reported a new stage or sampling step.
    case progress(GenerationProgress)
    /// A preview of the image being generated, decoded from the current latent.
    case preview(CGImage)
    /// The server is downloading model files before it can start.
    case remoteDownload(RemoteDownloadProgress)
    /// A final image was received (``GenerationResult/images`` has all of them).
    case image(CGImage, index: Int)
    /// A generated audio track was received (video models with sound).
    case audio(GeneratedAudio)
    /// The generation finished. Always the last event.
    case completed(GenerationResult)
}

/// Progress of model downloads the server performs before generating.
public struct RemoteDownloadProgress: Sendable, Hashable {
    public var bytesReceived: Int64
    public var bytesExpected: Int64
    /// The file being downloaded (0-based) and the number of files.
    public var item: Int
    public var itemCount: Int

    public init(bytesReceived: Int64, bytesExpected: Int64, item: Int, itemCount: Int) {
        self.bytesReceived = bytesReceived
        self.bytesExpected = bytesExpected
        self.item = item
        self.itemCount = itemCount
    }

    public var fractionCompleted: Double? {
        bytesExpected > 0 ? Double(bytesReceived) / Double(bytesExpected) : nil
    }
}
