//
//  MaskEncoder.swift
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

extension ImageHelpers {
    // MARK: - Mask Creation

    /// Creates an inpainting mask from an image's alpha channel
    public static func createMaskFromAlpha(_ image: PlatformImage) throws -> Data {
        guard let cgImage = image.cgImageRepresentation else {
            throw ImageError.invalidImage
        }
        return try createMaskFromAlpha(cgImage)
    }

    /// Creates a Draw Things inpainting mask from an image's alpha channel: transparent pixels
    /// are regenerated, opaque pixels are kept.
    ///
    /// The mask is a 1-byte-per-pixel CCV tensor (value 2 = inpaint, 0 = keep), not an RGB image
    /// tensor; sending an RGB tensor as a mask crashes the server's inpainting check.
    public static func createMaskFromAlpha(_ cgImage: CGImage) throws -> Data {
        let bitmap = try RGBA8Bitmap(cgImage)
        let width = bitmap.width
        let height = bitmap.height

        var mask = Data(count: TensorDecompression.headerSize + bitmap.pixelCount)
        let header: [Int32] = [0, 1, 1, 4096, 0, Int32(height), Int32(width), 0, 0]
        mask.withUnsafeMutableBytes { output in
            for (index, value) in header.enumerated() {
                output.storeBytes(of: value.littleEndian, toByteOffset: index * 4, as: Int32.self)
            }
            let values = output.baseAddress!.advanced(by: TensorDecompression.headerSize).assumingMemoryBound(to: UInt8.self)
            bitmap.pixels.withUnsafeBufferPointer { rgba in
                for index in 0..<bitmap.pixelCount {
                    values[index] = rgba[index * 4 + 3] < 255 ? 2 : 0
                }
            }
        }

        DTLogger.debug("🎭 Created inpainting mask from alpha channel: \(width)x\(height), size: \(mask.count) bytes", category: .images)
        return mask
    }
}
