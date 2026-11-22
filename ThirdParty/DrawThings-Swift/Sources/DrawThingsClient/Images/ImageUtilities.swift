//
//  ImageUtilities.swift
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
import ImageIO
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Image conversion helpers: DTTensor encoding and decoding, masks, and image utilities.
///
/// Every operation has a `CGImage` form, which is `Sendable` and works in exact pixels, and a
/// `PlatformImage` (`NSImage` / `UIImage`) convenience that wraps it. Results are always
/// rendered at one pixel per point, so sizes never depend on the screen's backing scale.
public enum ImageHelpers {}

extension ImageHelpers {
    // MARK: - Encoding and files

    /// PNG data for an image.
    public static func convertImageToData(_ image: PlatformImage) throws -> Data {
        try pngData(for: try cgImage(from: image))
    }

    /// PNG data for a `CGImage`.
    public static func pngData(for image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ImageError.conversionFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImageError.conversionFailed }
        return data as Data
    }

    /// Loads an image file and returns it as PNG data.
    public static func loadImageData(from url: URL) throws -> Data {
        try pngData(for: try loadCGImage(from: url))
    }

    /// Loads an image file and returns it as PNG data.
    public static func loadImageData(from path: String) throws -> Data {
        try loadImageData(from: URL(fileURLWithPath: path))
    }

    /// Loads an image file as an upright `CGImage`, applying its EXIF orientation.
    public static func loadCGImage(from url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageError.fileNotFound
        }
        return try uprightImage(from: source)
    }

    /// Decodes encoded image data (PNG, JPEG, HEIC...) as an upright `CGImage`, applying its
    /// EXIF orientation.
    public static func decodeCGImage(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageError.invalidData
        }
        return try uprightImage(from: source)
    }

    private static func uprightImage(from source: CGImageSource) throws -> CGImage {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? UInt32) ?? 1
        let image: CGImage?
        if orientation == 1 {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        } else {
            // A full-size "thumbnail" is the ImageIO way to get the orientation applied.
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: Int.max,
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
        guard let image else { throw ImageError.invalidImage }
        return image
    }

    /// Creates a platform image from encoded image data (PNG, JPEG, HEIC...).
    public static func dataToImage(_ data: Data) throws -> PlatformImage {
        guard let image = PlatformImage.fromData(data) else {
            throw ImageError.invalidData
        }
        return image
    }

    /// Saves an image as PNG or JPEG.
    ///
    /// - Parameters:
    ///   - image: The image to save.
    ///   - url: The destination file URL.
    ///   - format: `.png` or `.jpeg`.
    ///   - jpegQuality: JPEG compression quality (0.0-1.0), only used for `.jpeg`.
    public static func saveImage(_ image: PlatformImage, to url: URL, format: ImageFormat = .png, jpegQuality: Float = 0.9) throws {
        try saveImage(try cgImage(from: image), to: url, format: format, jpegQuality: jpegQuality)
    }

    /// Saves a `CGImage` as PNG or JPEG.
    ///
    /// - Parameters:
    ///   - image: The image to save.
    ///   - url: The destination file URL.
    ///   - format: `.png` or `.jpeg`.
    ///   - jpegQuality: JPEG compression quality (0.0-1.0), only used for `.jpeg`.
    public static func saveImage(_ image: CGImage, to url: URL, format: ImageFormat = .png, jpegQuality: Float = 0.9) throws {
        let type = format == .png ? UTType.png : UTType.jpeg
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ImageError.conversionFailed
        }
        var properties: [CFString: Any] = [:]
        if format == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = jpegQuality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageError.conversionFailed
        }
    }

    // MARK: - Resizing

    /// Resizes an image to exactly `size` pixels, ignoring aspect ratio.
    public static func resizeImage(_ image: PlatformImage, to size: CGSize) -> PlatformImage {
        guard let source = try? cgImage(from: image),
              let resized = resizedImage(source, width: Int(size.width), height: Int(size.height))
        else { return image }
        return PlatformImage.fromCGImage(resized)
    }

    /// Resizes a `CGImage` to exactly `width` × `height` pixels, ignoring aspect ratio.
    public static func resizedImage(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        render(width: width, height: height, background: nil) { context in
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// Scales an image to fit a canvas of `canvasWidth` × `canvasHeight` pixels, preserving its
    /// aspect ratio and centring it. Empty space is filled with `backgroundColor`, or left
    /// transparent when it is nil.
    public static func scaleImageToCanvas(_ image: PlatformImage, canvasWidth: Int, canvasHeight: Int, backgroundColor: PlatformColor?) -> PlatformImage {
        guard let source = try? cgImage(from: image),
              let scaled = scaledImageToCanvas(source, canvasWidth: canvasWidth, canvasHeight: canvasHeight,
                                               backgroundColor: backgroundColor?.cgColor)
        else { return image }
        return PlatformImage.fromCGImage(scaled)
    }

    /// Scales a `CGImage` to fit a canvas, preserving aspect ratio; see
    /// ``scaleImageToCanvas(_:canvasWidth:canvasHeight:backgroundColor:)``.
    public static func scaledImageToCanvas(_ image: CGImage, canvasWidth: Int, canvasHeight: Int, backgroundColor: CGColor?) -> CGImage? {
        guard canvasWidth > 0, canvasHeight > 0, image.width > 0, image.height > 0 else { return nil }
        if image.width == canvasWidth && image.height == canvasHeight {
            return image
        }
        let scale = min(Double(canvasWidth) / Double(image.width), Double(canvasHeight) / Double(image.height))
        let scaledWidth = Double(image.width) * scale
        let scaledHeight = Double(image.height) * scale
        let rect = CGRect(
            x: (Double(canvasWidth) - scaledWidth) / 2,
            y: (Double(canvasHeight) - scaledHeight) / 2,
            width: scaledWidth,
            height: scaledHeight
        )
        DTLogger.debug("scaleImageToCanvas: \(image.width)x\(image.height) -> \(canvasWidth)x\(canvasHeight), drawn at \(rect)", category: .images)
        return render(width: canvasWidth, height: canvasHeight, background: backgroundColor) { context in
            context.draw(image, in: rect)
        }
    }

    // MARK: - Transparency

    /// True if any pixel of the image is not fully opaque.
    public static func hasTransparency(_ image: PlatformImage) -> Bool {
        guard let cgImage = try? cgImage(from: image) else { return false }
        return hasTransparency(cgImage)
    }

    /// True if any pixel of the image is not fully opaque.
    public static func hasTransparency(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            return (try? RGBA8Bitmap(image))?.hasTransparency ?? false
        }
    }

    /// Composites the image over a solid color, removing transparency.
    public static func fillTransparentAreas(_ image: PlatformImage, fillColor: PlatformColor) -> PlatformImage {
        guard let source = try? cgImage(from: image),
              let filled = filledTransparentAreas(source, fillColor: fillColor.cgColor)
        else { return image }
        return PlatformImage.fromCGImage(filled)
    }

    /// Composites a `CGImage` over a solid color, removing transparency.
    public static func filledTransparentAreas(_ image: CGImage, fillColor: CGColor) -> CGImage? {
        render(width: image.width, height: image.height, background: fillColor) { context in
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
    }

    // MARK: - Helpers

    /// The pixels of a platform image as an upright `CGImage`.
    static func cgImage(from image: PlatformImage) throws -> CGImage {
        guard let cgImage = image.cgImageRepresentation else { throw ImageError.invalidImage }
        return cgImage
    }

    /// Draws into a new RGBA sRGB bitmap of exactly `width` × `height` pixels.
    static func render(width: Int, height: Int, background: CGColor?, draw: (CGContext) -> Void) -> CGImage? {
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .high
        if let background {
            context.setFillColor(background)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        draw(context)
        return context.makeImage()
    }
}

public enum ImageFormat: Sendable {
    case png
    case jpeg
}

// MARK: - Image Errors

public enum ImageError: Error, Sendable, LocalizedError {
    case invalidImage
    case invalidData
    case conversionFailed
    case fileNotFound

    public var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Invalid image format or corrupted image"
        case .invalidData:
            return "Invalid image data"
        case .conversionFailed:
            return "Failed to convert image to desired format"
        case .fileNotFound:
            return "Image file not found"
        }
    }
}
