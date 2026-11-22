//
//  TensorCodec.swift
//  DrawThingsClient
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import Accelerate
import CoreGraphics
import Foundation

extension ImageHelpers {
    // MARK: - DTTensor Conversion

    /// Convert a platform image to DTTensor format for Draw Things
    /// - Parameters:
    ///   - image: The source image
    ///   - forceRGB: If true, always output 3 channels (RGB) even if image has transparency
    /// - Returns: DTTensor data
    public static func imageToDTTensor(_ image: PlatformImage, forceRGB: Bool = false) throws -> Data {
        guard let cgImage = image.cgImageRepresentation else {
            throw ImageError.invalidImage
        }
        return try imageToDTTensor(cgImage, forceRGB: forceRGB)
    }

    /// Convert Sendable Core Graphics pixels to DTTensor format. This is the
    /// executor-neutral primitive used by queues that must keep full-image
    /// conversion off their UI actor.
    public static func imageToDTTensor(_ cgImage: CGImage, forceRGB: Bool = false) throws -> Data {
        let bitmap = try RGBA8Bitmap(cgImage)
        let channels = (!forceRGB && bitmap.hasTransparency) ? 4 : 3
        let valueCount = bitmap.pixelCount * channels

        DTLogger.debug("🖼️ Converting image: \(bitmap.width)x\(bitmap.height), \(channels) channels, forceRGB: \(forceRGB)", category: .images)

        // Header: 17 UInt32 values (uncompressed, CPU memory, NHWC, Float16, dims N H W C).
        var tensor = Data(count: TensorDecompression.headerSize + valueCount * 2)
        let header: [UInt32] = [0, 0x1, 0x02, 0x20000, 0, 1, UInt32(bitmap.height), UInt32(bitmap.width), UInt32(channels)]
        try tensor.withUnsafeMutableBytes { (output: UnsafeMutableRawBufferPointer) in
            for (index, value) in header.enumerated() {
                output.storeBytes(of: value.littleEndian, toByteOffset: index * 4, as: UInt32.self)
            }
            let payload = output.baseAddress!.advanced(by: TensorDecompression.headerSize)
            try bitmap.pixels.withUnsafeBytes { rgba in
                if channels == 4 {
                    try encodeFloat16(bytes: rgba.baseAddress!, count: valueCount, into: payload)
                } else {
                    // Drop alpha, then encode.
                    var rgb = [UInt8](repeating: 0, count: valueCount)
                    try rgb.withUnsafeMutableBytes { rgbBytes in
                        var source = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: rgba.baseAddress!),
                                                   height: vImagePixelCount(bitmap.height), width: vImagePixelCount(bitmap.width),
                                                   rowBytes: bitmap.bytesPerRow)
                        var destination = vImage_Buffer(data: rgbBytes.baseAddress!,
                                                        height: vImagePixelCount(bitmap.height), width: vImagePixelCount(bitmap.width),
                                                        rowBytes: bitmap.width * 3)
                        try check(vImageConvert_RGBA8888toRGB888(&source, &destination, vImage_Flags(kvImageNoFlags)))
                        try encodeFloat16(bytes: rgbBytes.baseAddress!, count: valueCount, into: payload)
                    }
                }
            }
        }

        DTLogger.debug("✅ DTTensor created: \(tensor.count) bytes", category: .images)
        return tensor
    }

    /// Maps 8-bit values 0...255 to Float16 -1...1 (`v / 255 * 2 - 1`) with Accelerate.
    private static func encodeFloat16(bytes: UnsafeRawPointer, count: Int, into output: UnsafeMutableRawPointer) throws {
        var floats = [Float](repeating: 0, count: count)
        try floats.withUnsafeMutableBytes { floatBytes in
            var source = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: bytes), height: 1,
                                       width: vImagePixelCount(count), rowBytes: count)
            var intermediate = vImage_Buffer(data: floatBytes.baseAddress!, height: 1,
                                             width: vImagePixelCount(count), rowBytes: count * 4)
            var destination = vImage_Buffer(data: output, height: 1, width: vImagePixelCount(count), rowBytes: count * 2)
            try check(vImageConvert_Planar8toPlanarF(&source, &intermediate, 1, -1, vImage_Flags(kvImageNoFlags)))
            try check(vImageConvert_PlanarFtoPlanar16F(&intermediate, &destination, vImage_Flags(kvImageNoFlags)))
        }
    }

    static func check(_ error: vImage_Error) throws {
        guard error == kvImageNoError else {
            DTLogger.error("vImage conversion failed: \(error)", category: .images)
            throw ImageError.conversionFailed
        }
    }

    /// Convert DTTensor data to a platform image
    /// - Parameters:
    ///   - tensorData: The DTTensor data from Draw Things
    ///   - modelFamily: Optional model family for correct latent-to-RGB conversion (defaults to .flux for 16-channel)
    /// - Returns: A platform image
    public static func dtTensorToImage(_ tensorData: Data, modelFamily: ModelFamily? = nil) throws -> PlatformImage {
        PlatformImage.fromCGImage(try dtTensorToCGImage(tensorData, modelFamily: modelFamily))
    }

    /// Convert DTTensor data (a decoded image or a preview latent) to a `CGImage`.
    ///
    /// This is the executor-neutral primitive behind ``dtTensorToImage(_:modelFamily:)``;
    /// `CGImage` is `Sendable`, so it is safe to call off the main actor.
    public static func dtTensorToCGImage(_ tensorData: Data, modelFamily: ModelFamily? = nil) throws -> CGImage {
        guard tensorData.count >= 68 else {
            throw ImageError.invalidData
        }

        // Decompress if needed (handles deflate and fpzip compression), and make sure the
        // Float16 payload is 2-byte aligned for the typed reads below.
        var tensorData = try TensorDecompression.decompressIfNeeded(tensorData)
        let isAligned = tensorData.withUnsafeBytes { Int(bitPattern: $0.baseAddress) % MemoryLayout<UInt16>.alignment == 0 }
        if !isAligned { tensorData = Data(Array(tensorData)) }

        let header: [UInt32] = tensorData.withUnsafeBytes { raw in
            (0..<17).map { raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self) }
        }

        let format = header[2]  // 0x02 = NHWC, other = NCHW
        var height = Int(header[6])
        let width = Int(header[7])
        let channels = Int(header[8])
        let dim0 = Int(header[5])
        let isNHWC = (format == 0x02)

        // Header values come from the network: reject sizes that are zero, absurd or overflow.
        let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (valueCount, valueOverflow) = pixelCount.multipliedReportingOverflow(by: max(channels, 1))
        guard width > 0, height > 0, channels > 0, !pixelOverflow, !valueOverflow,
              valueCount <= TensorDecompression.maxElements
        else {
            DTLogger.error("dtTensorToImage: invalid tensor dimensions \(dim0)x\(height)x\(width)x\(channels)", category: .images)
            throw ImageError.invalidData
        }

        // Audio latent rows are packed below the video latent in preview latents only; decoded
        // RGB (3-channel) and RGBA (4-channel) frames have no audio rows and must not be cropped.
        let isLatent = channels > 4

        // For LTX-2 preview latents, strip audio latent rows from the bottom
        let family = modelFamily ?? .unknown
        if (family == .ltx2 || family == .ltx23) && isLatent && dim0 > 0 && width > 0 {
            let (_, audioHeight) = ltx2ExtractAudioFramesAndHeight(
                dim0: dim0, height: height, width: width
            )
            if audioHeight > 0 && audioHeight < height {
                DTLogger.debug("dtTensorToImage: stripping \(audioHeight) audio latent rows from LTX-2 preview (height \(height) -> \(height - audioHeight))", category: .images)
                height -= audioHeight
            }
        }

        // MiniMax H3 packs audio latent rows below its 24-channel video latent in the same way.
        // Key on the channel count so a 24-channel latent is handled even without a family hint.
        if channels == 24 && dim0 > 0 && width > 0 {
            let audioHeight = minimaxH3AudioHeight(videoLatentFrames: dim0, latentWidth: width)
            if audioHeight > 0 && audioHeight < height {
                DTLogger.debug("dtTensorToImage: stripping \(audioHeight) audio latent rows from MiniMax H3 preview (height \(height) -> \(height - audioHeight))", category: .images)
                height -= audioHeight
            }
        }

        // HiDream-O1 uses a patch-packed latent (3 × 32 × 32 channels) decoded into an
        // image 32× larger per side, not a coefficient matrix. Handle it before the
        // standard channel guard, keyed on the family or the distinctive channel count.
        if family == .hiDreamO1 || channels == 3 * 32 * 32 {
            DTLogger.debug("dtTensorToImage: using HiDream-O1 patch-based conversion", category: .images)
            return try hiDreamO1PatchToCGImage(tensorData, imageWidth: width, imageHeight: height, channels: channels)
        }

        // Models with a transparent (RGBA) decoder, such as Qwen Image 2.1, return final images as
        // 4-channel ARGB tensors. For a family whose latent isn't 4-channel, a 4-channel tensor
        // can only be decoded pixels, so it must not go through the 4-channel latent conversion.
        if channels == 4 && family != .unknown && family.latentChannels != 4 {
            DTLogger.debug("dtTensorToImage: using 4-channel ARGB conversion (family=\(family))", category: .images)
            return try argbTensorToCGImage(tensorData, width: width, height: height, isNHWC: isNHWC)
        }

        guard channels == 3 || channels == 4 || channels == 16 || channels == 24 || channels == 32 || channels == 48 || channels == 64 else {
            DTLogger.error("dtTensorToImage: unsupported channel count \(channels)", category: .images)
            throw ImageError.conversionFailed
        }

        let pixelDataOffset = 68
        let expectedDataSize = pixelDataOffset + (width * height * channels * 2)

        guard tensorData.count >= expectedDataSize else {
            throw ImageError.invalidData
        }

        DTLogger.debug("dtTensorToImage: \(width)x\(height), \(channels) channels, modelFamily=\(modelFamily?.rawValue ?? "nil")", category: .images)

        // Output RGB data
        var rgbData = Data(count: width * height * 3)

        tensorData.withUnsafeBytes { (rawPtr: UnsafeRawBufferPointer) in
            let basePtr = rawPtr.baseAddress!.advanced(by: pixelDataOffset)
            let float16Ptr = basePtr.assumingMemoryBound(to: UInt16.self)

            rgbData.withUnsafeMutableBytes { (outPtr: UnsafeMutableRawBufferPointer) in
                let uint8Ptr = outPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)

                if channels == 64 {
                    // 64-channel latent space to RGB (Qwen Image 2.1 coefficients)
                    DTLogger.debug("dtTensorToImage: using 64-channel Qwen Image 2.1 conversion", category: .images)
                    convertQwen21ToRGB(float16Ptr: float16Ptr, uint8Ptr: uint8Ptr, pixelCount: width * height)
                } else if channels == 48 {
                    // 48-channel latent space to RGB (Wan 2.2 5B coefficients)
                    DTLogger.debug("dtTensorToImage: using 48-channel Wan 2.2 conversion", category: .images)
                    convert48ChannelToRGB(float16Ptr: float16Ptr, uint8Ptr: uint8Ptr, pixelCount: width * height)
                } else if channels == 24 {
                    // 24-channel latent space to RGB (MiniMax H3 coefficients)
                    DTLogger.debug("dtTensorToImage: using 24-channel MiniMax H3 conversion", category: .images)
                    convertMiniMaxH3ToRGB(float16Ptr: float16Ptr, uint8Ptr: uint8Ptr, pixelCount: width * height)
                } else if channels == 32 {
                    // 32-channel latent space to RGB (Flux 2 coefficients)
                    DTLogger.debug("dtTensorToImage: using 32-channel Flux 2 conversion", category: .images)
                    convertFlux2ToRGB(float16Ptr: float16Ptr, uint8Ptr: uint8Ptr, pixelCount: width * height)
                } else if channels == 16 {
                    // 16-channel latent space to RGB - use model-specific coefficients
                    let family = modelFamily ?? .flux
                    switch family {
                    case .qwen, .wan21, .longcatVideoAvatar:
                        DTLogger.debug("dtTensorToImage: using Qwen/Wan21 16-channel conversion", category: .images)
                        convertQwenWan21ToRGB(float16Ptr: float16Ptr, uint8Ptr: uint8Ptr, pixelCount: width * height)
                    case .sd3:
                        DTLogger.debug("dtTensorToImage: using SD3 16-channel conversion", category: .images)
                        convertSD3ToRGB(float16Ptr: float16Ptr, uint8Ptr: uint8Ptr, pixelCount: width * height)
                    case .hunyuanVideo:
                        DTLogger.debug("dtTensorToImage: using HunyuanVideo 16-channel conversion", category: .images)
                        convertHunyuanVideoToRGB(float16Ptr: float16Ptr, uint8Ptr: uint8Ptr, pixelCount: width * height)
                    case .ltx2, .ltx23:
                        // LTX-2/2.3 uses Flux-like coefficients as a reasonable fallback
                        DTLogger.debug("dtTensorToImage: using Flux 16-channel conversion for LTX fallback", category: .images)
                        convertFluxToRGB(float16Ptr: float16Ptr, uint8Ptr: uint8Ptr, pixelCount: width * height)
                    case .flux, .zImage, .unknown:
                        // Z Image uses Flux-like latent space
                        DTLogger.debug("dtTensorToImage: using Flux 16-channel conversion (family=\(family))", category: .images)
                        convertFluxToRGB(float16Ptr: float16Ptr, uint8Ptr: uint8Ptr, pixelCount: width * height)
                    default:
                        // Default to Flux coefficients for other 16-channel models
                        DTLogger.debug("dtTensorToImage: using Flux 16-channel conversion (default for \(family))", category: .images)
                        convertFluxToRGB(float16Ptr: float16Ptr, uint8Ptr: uint8Ptr, pixelCount: width * height)
                    }
                } else if channels == 4 {
                    // 4-channel latent space to RGB - coefficients differ by family.
                    switch family {
                    case .sd1:
                        // SD 1.x / 2.x / SVD use a distinct matrix from SDXL.
                        DTLogger.debug("dtTensorToImage: using 4-channel SD1 conversion", category: .images)
                        convertSD1ToRGB(float16Ptr: float16Ptr, uint8Ptr: uint8Ptr, pixelCount: width * height)
                    case .kandinsky:
                        DTLogger.debug("dtTensorToImage: using 4-channel Kandinsky (OKLab) conversion", category: .images)
                        convertKandinskyToRGB(float16Ptr: float16Ptr, uint8Ptr: uint8Ptr, pixelCount: width * height)
                    case .wurstchen:
                        DTLogger.debug("dtTensorToImage: using 4-channel Würstchen conversion", category: .images)
                        convertWurstchenToRGB(float16Ptr: float16Ptr, uint8Ptr: uint8Ptr, pixelCount: width * height)
                    default:
                        // SDXL / SSD-1B / PixArt / AuraFlow / unknown.
                        DTLogger.debug("dtTensorToImage: using 4-channel SDXL conversion (family=\(family))", category: .images)
                        convert4ChannelToRGB(float16Ptr: float16Ptr, uint8Ptr: uint8Ptr, pixelCount: width * height)
                    }
                } else {
                    // 3-channel RGB: Convert from [-1, 1] to [0, 255]
                    if isNHWC {
                        convert3ChannelToRGBAccelerated(float16Ptr: float16Ptr, uint8Ptr: uint8Ptr, count: width * height * channels)
                    } else {
                        // NCHW (planar): channels are stored as [R...R, G...G, B...B]
                        convert3ChannelNCHWToRGB(float16Ptr: float16Ptr, uint8Ptr: uint8Ptr, width: width, height: height)
                    }
                }
            }
        }

        return try makeRGBCGImage(rgbData, width: width, height: height)
    }

    static func makeRGBCGImage(_ rgbData: Data, width: Int, height: Int) throws -> CGImage {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: rgbData as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 24,
                bytesPerRow: width * 3,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw ImageError.conversionFailed
        }
        return cgImage
    }

    /// Convert a 4-channel ARGB pixel tensor (as produced by Draw Things' transparent decoders) to an RGBA image.
    ///
    /// Channel 0 is alpha in [0, 1]; channels 1...3 are RGB in [-1, 1]. Mirrors upstream
    /// `ImageConverter.imageAndMask(from:)` / the transparent `FirstStage` decode.
    static func argbTensorToCGImage(_ tensorData: Data, width: Int, height: Int, isNHWC: Bool) throws -> CGImage {
        let pixelDataOffset = 68
        let pixelCount = width * height
        guard pixelCount > 0, tensorData.count >= pixelDataOffset + pixelCount * 4 * 2 else {
            throw ImageError.invalidData
        }

        var rgbaData = Data(count: pixelCount * 4)
        tensorData.withUnsafeBytes { (rawPtr: UnsafeRawBufferPointer) in
            let float16Ptr = rawPtr.baseAddress!.advanced(by: pixelDataOffset).assumingMemoryBound(to: UInt16.self)
            rgbaData.withUnsafeMutableBytes { (outPtr: UnsafeMutableRawBufferPointer) in
                let uint8Ptr = outPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
                // NHWC: [A, R, G, B] per pixel; NCHW: planar [A...A, R...R, G...G, B...B]
                let (pixelStride, channelStride) = isNHWC ? (4, 1) : (1, pixelCount)
                for i in 0..<pixelCount {
                    let base = i * pixelStride
                    let a = f16ToFloat(float16Ptr, base)
                    let r = f16ToFloat(float16Ptr, base + channelStride)
                    let g = f16ToFloat(float16Ptr, base + 2 * channelStride)
                    let b = f16ToFloat(float16Ptr, base + 3 * channelStride)
                    uint8Ptr[i * 4 + 0] = UInt8(clamping: Int(r.isFinite ? (r + 1.0) * 127.5 : 127.5))
                    uint8Ptr[i * 4 + 1] = UInt8(clamping: Int(g.isFinite ? (g + 1.0) * 127.5 : 127.5))
                    uint8Ptr[i * 4 + 2] = UInt8(clamping: Int(b.isFinite ? (b + 1.0) * 127.5 : 127.5))
                    uint8Ptr[i * 4 + 3] = UInt8(clamping: Int((a.isFinite ? a : 1.0) * 255.0 + 0.5))
                }
            }
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: rgbaData as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw ImageError.conversionFailed
        }
        return cgImage
    }

    /// Maps Float16 values in -1...1 to 8-bit 0...255 with Accelerate (clamping out-of-range
    /// values), falling back to the scalar path if vImage fails. Used for full-size final images.
    static func convert3ChannelToRGBAccelerated(float16Ptr: UnsafePointer<UInt16>, uint8Ptr: UnsafeMutablePointer<UInt8>, count: Int) {
        var floats = [Float](repeating: 0, count: count)
        let succeeded = floats.withUnsafeMutableBytes { floatBytes -> Bool in
            var source = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: float16Ptr), height: 1,
                                       width: vImagePixelCount(count), rowBytes: count * 2)
            var intermediate = vImage_Buffer(data: floatBytes.baseAddress!, height: 1,
                                             width: vImagePixelCount(count), rowBytes: count * 4)
            var destination = vImage_Buffer(data: uint8Ptr, height: 1, width: vImagePixelCount(count), rowBytes: count)
            return vImageConvert_Planar16FtoPlanarF(&source, &intermediate, vImage_Flags(kvImageNoFlags)) == kvImageNoError
                && vImageConvert_PlanarFtoPlanar8(&intermediate, &destination, 1, -1, vImage_Flags(kvImageNoFlags)) == kvImageNoError
        }
        if !succeeded {
            convert3ChannelToRGB(float16Ptr: float16Ptr, uint8Ptr: uint8Ptr, pixelCount: count)
        }
    }
}
