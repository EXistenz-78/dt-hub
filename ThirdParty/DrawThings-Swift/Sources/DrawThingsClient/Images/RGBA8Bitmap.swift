//
//  RGBA8Bitmap.swift
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

/// A `CGImage` rendered into owned 8-bit RGBA (premultiplied alpha, sRGB) pixels.
///
/// The pixel buffer is only handed to Core Graphics inside a scoped pointer, so the context never
/// writes through a pointer that outlived its scope.
struct RGBA8Bitmap {
    let width: Int
    let height: Int
    /// `width * height * 4` bytes, rows top to bottom, R G B A per pixel.
    let pixels: [UInt8]

    var bytesPerRow: Int { width * 4 }
    var pixelCount: Int { width * height }

    init(_ image: CGImage) throws {
        let width = image.width
        let height = image.height
        let (count, overflow) = width.multipliedReportingOverflow(by: height * 4)
        guard width > 0, height > 0, !overflow, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw ImageError.invalidImage
        }
        var pixels = [UInt8](repeating: 0, count: count)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw ImageError.conversionFailed }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// True if any pixel is not fully opaque.
    var hasTransparency: Bool {
        stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] < 255 }
    }
}
