import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import DrawThingsClient

@Suite("Image pipeline")
struct ImagePipelineTests {
    /// A `width` × `height` image: left half red, right half blue, optionally with a transparent
    /// top-left pixel.
    private func testImage(width: Int, height: Int, transparentCorner: Bool = false) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        if transparentCorner {
            // CG's origin is bottom-left, so the top row is y = height - 1.
            context.clear(CGRect(x: 0, y: height - 1, width: 1, height: 1))
        }
        return try #require(context.makeImage())
    }

    @Test func resizeProducesExactPixelSize() throws {
        let resized = try #require(ImageHelpers.resizedImage(try testImage(width: 64, height: 32), width: 100, height: 50))
        #expect(resized.width == 100)
        #expect(resized.height == 50)
    }

    @Test func platformResizeIsIndependentOfScreenScale() throws {
        let image = PlatformImage.fromCGImage(try testImage(width: 64, height: 64))
        let resized = ImageHelpers.resizeImage(image, to: CGSize(width: 128, height: 96))
        #expect(resized.pixelWidth == 128)
        #expect(resized.pixelHeight == 96)
    }

    @Test func canvasLetterboxesToExactSize() throws {
        let canvas = try #require(ImageHelpers.scaledImageToCanvas(
            try testImage(width: 200, height: 100), canvasWidth: 128, canvasHeight: 128,
            backgroundColor: CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)))
        #expect(canvas.width == 128)
        #expect(canvas.height == 128)
        let bitmap = try RGBA8Bitmap(canvas)
        // Top row is background (green); the middle row starts with the image's red half.
        #expect(Array(bitmap.pixels[0..<3]) == [0, 255, 0])
        let middle = 64 * bitmap.bytesPerRow
        #expect(Array(bitmap.pixels[middle..<(middle + 3)]) == [255, 0, 0])
    }

    @Test func canvasReturnsSameSizedImageUnchanged() throws {
        let image = try testImage(width: 64, height: 64)
        #expect(ImageHelpers.scaledImageToCanvas(image, canvasWidth: 64, canvasHeight: 64, backgroundColor: nil) === image)
    }

    @Test func transparencyDetectionAndFill() throws {
        let opaque = try testImage(width: 8, height: 8)
        let transparent = try testImage(width: 8, height: 8, transparentCorner: true)
        #expect(!ImageHelpers.hasTransparency(opaque))
        #expect(ImageHelpers.hasTransparency(transparent))
        let filled = try #require(ImageHelpers.filledTransparentAreas(transparent, fillColor: CGColor(gray: 1, alpha: 1)))
        #expect(!ImageHelpers.hasTransparency(filled))
    }

    @Test func maskMarksTransparentPixelsForInpainting() throws {
        let mask = try ImageHelpers.createMaskFromAlpha(try testImage(width: 4, height: 2, transparentCorner: true))
        #expect(mask.count == 68 + 8)
        let dims = mask.withUnsafeBytes { raw in (5...6).map { raw.loadUnaligned(fromByteOffset: $0 * 4, as: Int32.self) } }
        #expect(dims == [2, 4])
        #expect(Array(mask.suffix(8)) == [2, 0, 0, 0, 0, 0, 0, 0])
    }

    @Test func decodingAppliesEXIFOrientation() throws {
        // Encode a 40x20 image as JPEG tagged "rotate 90° clockwise" (orientation 6).
        let source = try testImage(width: 40, height: 20)
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, source, [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))

        let decoded = try ImageHelpers.decodeCGImage(data as Data)
        #expect(decoded.width == 20)
        #expect(decoded.height == 40)
    }

    @Test func hintsKeepFirstAddedTypeOrder() throws {
        let png = try ImageHelpers.pngData(for: try testImage(width: 8, height: 8))
        var builder = HintBuilder()
        builder.addPose(png)
        builder.addDepthMap(png, weight: 0.5)
        builder.addPose(png, weight: 0.25)
        builder.addMoodboardImage(png)

        let hints = try builder.build()
        #expect(hints.map(\.hintType) == ["pose", "depth", "shuffle"])
        #expect(hints[0].tensors.map(\.weight) == [1, 0.25])
        #expect(hints[1].tensors.first?.weight == 0.5)
    }

    @Test func hintsReportUndecodableImages() throws {
        let png = try ImageHelpers.pngData(for: try testImage(width: 8, height: 8))
        var builder = HintBuilder()
        builder.addDepthMap(png)
        builder.addPose(Data("not an image".utf8))
        #expect(throws: HintBuildError.self) { try builder.build() }
        do {
            _ = try builder.build()
        } catch let error as HintBuildError {
            #expect(error.index == 1)
            #expect(error.type == "pose")
        }
    }
}
