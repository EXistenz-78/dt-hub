//
//  HintBuilder.swift
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

// MARK: - HintType

/// Control hint types understood by Draw Things.
public enum HintType: String, CaseIterable, Sendable {
    case shuffle
    case depth
    case pose
    case canny
    case scribble
    case color
    case lineart
    case softedge
    case seg
    case inpaint
    case ip2p
    case mlsd
    case tile
    case blur
    case lowquality
    case gray
    case custom
}

// MARK: - HintData

/// One hint image with its type and weight.
public struct HintData: Sendable {
    public let type: String
    /// Encoded image data (PNG, JPEG, HEIC...).
    public let imageData: Data
    public let weight: Float

    public init(type: String, imageData: Data, weight: Float = 1.0) {
        self.type = type
        self.imageData = imageData
        self.weight = weight
    }
}

/// A hint image that could not be decoded.
public struct HintBuildError: Error, Sendable, LocalizedError {
    /// Position of the hint in the order it was added.
    public let index: Int
    public let type: String
    public let reason: String

    public var errorDescription: String? {
        "Hint \(index) (\(type)) could not be converted: \(reason)"
    }
}

// MARK: - HintBuilder

/// Collects control hints (moodboard, depth, pose...) and encodes them for a request.
///
/// ```swift
/// var hints = HintBuilder()
/// hints.addDepthMap(depthPNG)
/// hints.addMoodboardImages([styleA, styleB], weight: 0.6)
/// let request = GenerationRequest(prompt: "...", hints: try hints.build())
/// ```
public struct HintBuilder: Sendable {
    private var hints: [HintData] = []

    public init(_ hints: [HintData] = []) {
        self.hints = hints
    }

    public var count: Int { hints.count }
    public var isEmpty: Bool { hints.isEmpty }

    // MARK: - Typed Hint Methods

    public mutating func addMoodboardImage(_ imageData: Data, weight: Float = 1.0) {
        addHint(type: .shuffle, imageData: imageData, weight: weight)
    }

    public mutating func addMoodboardImages(_ images: [Data], weight: Float = 1.0) {
        for imageData in images {
            addHint(type: .shuffle, imageData: imageData, weight: weight)
        }
    }

    public mutating func addDepthMap(_ imageData: Data, weight: Float = 1.0) {
        addHint(type: .depth, imageData: imageData, weight: weight)
    }

    public mutating func addPose(_ imageData: Data, weight: Float = 1.0) {
        addHint(type: .pose, imageData: imageData, weight: weight)
    }

    public mutating func addCannyEdges(_ imageData: Data, weight: Float = 1.0) {
        addHint(type: .canny, imageData: imageData, weight: weight)
    }

    public mutating func addScribble(_ imageData: Data, weight: Float = 1.0) {
        addHint(type: .scribble, imageData: imageData, weight: weight)
    }

    public mutating func addColorReference(_ imageData: Data, weight: Float = 1.0) {
        addHint(type: .color, imageData: imageData, weight: weight)
    }

    public mutating func addLineArt(_ imageData: Data, weight: Float = 1.0) {
        addHint(type: .lineart, imageData: imageData, weight: weight)
    }

    // MARK: - Generic Hint Methods

    public mutating func addHint(type: HintType, imageData: Data, weight: Float = 1.0) {
        addHint(type: type.rawValue, imageData: imageData, weight: weight)
    }

    public mutating func addHint(type: String, imageData: Data, weight: Float = 1.0) {
        hints.append(HintData(type: type, imageData: imageData, weight: weight))
    }

    public mutating func removeAll() {
        hints.removeAll()
    }

    // MARK: - Build

    /// Encodes the hints as DTTensors, grouped by type in the order each type was first added.
    ///
    /// - Throws: ``HintBuildError`` if an image cannot be decoded; no hint is silently dropped.
    public func build() throws -> [HintProto] {
        var order: [String] = []
        var tensorsByType: [String: [TensorAndWeight]] = [:]

        for (index, hint) in hints.enumerated() {
            let image: CGImage
            do {
                image = try ImageHelpers.decodeCGImage(hint.imageData)
            } catch {
                throw HintBuildError(index: index, type: hint.type, reason: "not a readable image")
            }
            let tensor: Data
            do {
                tensor = try ImageHelpers.imageToDTTensor(image, forceRGB: true)
            } catch {
                throw HintBuildError(index: index, type: hint.type, reason: error.localizedDescription)
            }
            if tensorsByType[hint.type] == nil { order.append(hint.type) }
            tensorsByType[hint.type, default: []].append(TensorAndWeight.with {
                $0.tensor = tensor
                $0.weight = hint.weight
            })
        }

        return order.map { type in
            HintProto.with {
                $0.hintType = type
                $0.tensors = tensorsByType[type] ?? []
            }
        }
    }
}
