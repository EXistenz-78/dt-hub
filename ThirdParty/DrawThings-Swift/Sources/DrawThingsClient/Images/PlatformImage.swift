//
//  PlatformImage.swift
//  DrawThingsClient
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import Foundation
import CoreGraphics
import UniformTypeIdentifiers
#if canImport(CoreImage)
import CoreImage
#endif

#if os(macOS)
import AppKit
public typealias PlatformImage = NSImage
public typealias PlatformColor = NSColor
#else
import UIKit
public typealias PlatformImage = UIImage
public typealias PlatformColor = UIColor
#endif

// MARK: - Platform Image Extensions

extension PlatformImage {
    /// Create a platform image from Data
    public static func fromData(_ data: Data) -> PlatformImage? {
        #if os(macOS)
        return NSImage(data: data)
        #else
        return UIImage(data: data)
        #endif
    }

    /// Wraps a `CGImage` at 1 point per pixel.
    public static func fromCGImage(_ cgImage: CGImage) -> PlatformImage {
        #if os(macOS)
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        #else
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
        #endif
    }

    #if os(macOS)
    /// Convert to PNG data
    public func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
    #endif
    // Note: On iOS, UIImage already has pngData() built-in, so no extension needed

    /// Width in pixels of ``cgImageRepresentation``.
    public var pixelWidth: Int { cgImageRepresentation?.width ?? 0 }

    /// Height in pixels of ``cgImageRepresentation``.
    public var pixelHeight: Int { cgImageRepresentation?.height ?? 0 }

    /// The image's pixels as an upright `CGImage`.
    ///
    /// On iOS this applies `imageOrientation` (photos from the camera are usually stored
    /// rotated) and renders images backed by a `CIImage`, which have no `cgImage`. Use it
    /// whenever pixels are sent to the server; `UIImage.cgImage` alone would send them sideways.
    public var cgImageRepresentation: CGImage? {
        #if os(macOS)
        return cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        if imageOrientation == .up, let cgImage {
            return cgImage
        }
        if cgImage == nil, let ciImage {
            return CIContext().createCGImage(ciImage, from: ciImage.extent)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
        #endif
    }
}
