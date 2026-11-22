//
//  LatentPreview.swift
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
    // MARK: - LTX-2 Audio Latent Stripping

    /// Compute the number of audio frames and audio latent height for LTX-2 tensors.
    ///
    /// Ports the upstream `LTX2ExtractAudioFramesAndHeight` function.
    /// Audio latent rows are appended at the bottom of the video latent tensor
    /// and must be stripped before preview conversion.
    static func ltx2ExtractAudioFramesAndHeight(
        dim0: Int, height: Int, width: Int
    ) -> (audioFrames: Int, audioHeight: Int) {
        let audioFrames = (dim0 - 1) * 8 + 1
        let audioHeight = (audioFrames + width * dim0 - 1) / (width * dim0)
        return (audioFrames, audioHeight)
    }

    // MARK: - MiniMax H3 Audio Latent Stripping

    /// Compute the number of audio latent rows packed below a MiniMax H3 video latent.
    ///
    /// Ports the upstream `MiniMaxH3AudioHeight` function. The video latent has 24 channels
    /// at 24 fps; audio is 32-channel at 40 rows per second, appended as extra rows.
    /// Returns 0 for a frame count the upstream function would not accept.
    static func minimaxH3AudioHeight(videoLatentFrames: Int, latentWidth: Int) -> Int {
        let videoChannels = 24
        let audioChannels = 32
        let framesPerSecond = 24
        guard latentWidth > 0 else { return 0 }
        guard videoLatentFrames == 1 || videoLatentFrames == 2
            || (videoLatentFrames >= 7 && (videoLatentFrames - 2) % 5 == 0) else {
            return 0
        }
        let frames = videoLatentFrames == 1 ? 1 : (videoLatentFrames - 2) / 5 * 17 + 5
        let rows = 2 * Int((Double(frames) / Double(framesPerSecond) * 40).rounded())
        let rowSize = videoLatentFrames * latentWidth * videoChannels
        let audioSize = rows * audioChannels
        var height = (audioSize + rowSize - 1) / rowSize
        while height * rowSize % audioChannels != 0 {
            height += 1
        }
        return height
    }

    // MARK: - Model-Specific Latent Conversion Functions

    /// Helper to convert Float16 bit pattern to Float - works on all platforms
    @inline(__always)
    static func f16ToFloat(_ ptr: UnsafePointer<UInt16>, _ index: Int) -> Float {
        let bits: UInt16 = ptr[index]
        return float16BitsToFloat(bits)
    }

    /// Convert Float16 bit pattern to Float32 manually (platform-independent)
    @inline(__always)
    static func float16BitsToFloat(_ h: UInt16) -> Float {
        let sign = UInt32((h >> 15) & 0x1)
        let exponent = UInt32((h >> 10) & 0x1F)
        let mantissa = UInt32(h & 0x3FF)

        var result: UInt32

        if exponent == 0 {
            if mantissa == 0 {
                // Zero
                result = sign << 31
            } else {
                // Denormalized number - convert to normalized
                var exp = Int32(-14)
                var mant = mantissa
                while (mant & 0x400) == 0 {
                    mant <<= 1
                    exp -= 1
                }
                mant &= 0x3FF
                result = (sign << 31) | (UInt32(Int32(127) + exp) << 23) | (mant << 13)
            }
        } else if exponent == 31 {
            // Infinity or NaN
            result = (sign << 31) | 0x7F800000 | (mantissa << 13)
        } else {
            // Normalized number
            result = (sign << 31) | ((exponent + 112) << 23) | (mantissa << 13)
        }

        return Float(bitPattern: result)
    }

    /// Convert Float32 to Float16 bit pattern manually (platform-independent)
    @inline(__always)
    static func floatToFloat16Bits(_ f: Float) -> UInt16 {
        let bits = f.bitPattern
        let sign = UInt16((bits >> 31) & 0x1)
        let exponent = Int32((bits >> 23) & 0xFF)
        let mantissa = bits & 0x7FFFFF

        var result: UInt16

        if exponent == 0 {
            // Zero or denormalized (becomes zero in float16)
            result = sign << 15
        } else if exponent == 255 {
            // Infinity or NaN
            result = (sign << 15) | 0x7C00 | UInt16((mantissa >> 13) & 0x3FF)
        } else {
            // Normalized number
            let newExp = exponent - 127 + 15
            if newExp <= 0 {
                // Underflow to zero
                result = sign << 15
            } else if newExp >= 31 {
                // Overflow to infinity
                result = (sign << 15) | 0x7C00
            } else {
                result = (sign << 15) | (UInt16(newExp) << 10) | UInt16((mantissa >> 13) & 0x3FF)
            }
        }

        return result
    }

    /// Convert 4-channel SDXL latent to RGB
    static func convert4ChannelToRGB(float16Ptr: UnsafePointer<UInt16>, uint8Ptr: UnsafeMutablePointer<UInt8>, pixelCount: Int) {
        for i in 0..<pixelCount {
            let base = i * 4
            let v0 = f16ToFloat(float16Ptr, base + 0)
            let v1 = f16ToFloat(float16Ptr, base + 1)
            let v2 = f16ToFloat(float16Ptr, base + 2)
            let v3 = f16ToFloat(float16Ptr, base + 3)

            let r: Float = 47.195 * v0 - 29.114 * v1 + 11.883 * v2 - 38.063 * v3 + 141.64
            let g: Float = 53.237 * v0 - 1.4623 * v1 + 12.991 * v2 - 28.043 * v3 + 127.46
            let b: Float = 58.182 * v0 + 4.3734 * v1 - 3.3735 * v2 - 26.722 * v3 + 114.5

            uint8Ptr[i * 3 + 0] = UInt8(clamping: Int(r.isFinite ? r : 0))
            uint8Ptr[i * 3 + 1] = UInt8(clamping: Int(g.isFinite ? g : 0))
            uint8Ptr[i * 3 + 2] = UInt8(clamping: Int(b.isFinite ? b : 0))
        }
    }

    /// Convert 4-channel SD 1.x / 2.x / SVD latent to RGB.
    ///
    /// These use a different matrix than SDXL (upstream `v1`/`v2`/`svd_i2v` case).
    static func convertSD1ToRGB(float16Ptr: UnsafePointer<UInt16>, uint8Ptr: UnsafeMutablePointer<UInt8>, pixelCount: Int) {
        for i in 0..<pixelCount {
            let base = i * 4
            let v0 = f16ToFloat(float16Ptr, base + 0)
            let v1 = f16ToFloat(float16Ptr, base + 1)
            let v2 = f16ToFloat(float16Ptr, base + 2)
            let v3 = f16ToFloat(float16Ptr, base + 3)

            let r: Float = 49.5210 * v0 + 29.0283 * v1 - 23.9673 * v2 - 39.4981 * v3 + 99.9368
            let g: Float = 41.1373 * v0 + 42.4951 * v1 + 24.7349 * v2 - 50.8279 * v3 + 99.8421
            let b: Float = 40.2919 * v0 + 18.9304 * v1 + 30.0236 * v2 - 81.9976 * v3 + 99.5384

            uint8Ptr[i * 3 + 0] = UInt8(clamping: Int(r.isFinite ? r : 0))
            uint8Ptr[i * 3 + 1] = UInt8(clamping: Int(g.isFinite ? g : 0))
            uint8Ptr[i * 3 + 2] = UInt8(clamping: Int(b.isFinite ? b : 0))
        }
    }

    /// Convert 4-channel Würstchen / Stable Cascade latent to RGB.
    static func convertWurstchenToRGB(float16Ptr: UnsafePointer<UInt16>, uint8Ptr: UnsafeMutablePointer<UInt8>, pixelCount: Int) {
        for i in 0..<pixelCount {
            let base = i * 4
            let v0 = f16ToFloat(float16Ptr, base + 0)
            let v1 = f16ToFloat(float16Ptr, base + 1)
            let v2 = f16ToFloat(float16Ptr, base + 2)
            let v3 = f16ToFloat(float16Ptr, base + 3)

            let r: Float = 10.175 * v0 - 20.807 * v1 - 27.834 * v2 - 2.0577 * v3 + 143.39
            let g: Float = 21.07 * v0 - 4.3022 * v1 - 11.258 * v2 - 18.8 * v3 + 131.53
            let b: Float = 7.8454 * v0 - 2.3713 * v1 - 0.45565 * v2 - 41.648 * v3 + 120.76

            uint8Ptr[i * 3 + 0] = UInt8(clamping: Int(r.isFinite ? r : 0))
            uint8Ptr[i * 3 + 1] = UInt8(clamping: Int(g.isFinite ? g : 0))
            uint8Ptr[i * 3 + 2] = UInt8(clamping: Int(b.isFinite ? b : 0))
        }
    }

    /// Convert 4-channel Kandinsky 2.1 latent to RGB via the OKLab color space.
    static func convertKandinskyToRGB(float16Ptr: UnsafePointer<UInt16>, uint8Ptr: UnsafeMutablePointer<UInt8>, pixelCount: Int) {
        for i in 0..<pixelCount {
            let base = i * 4
            let v0 = f16ToFloat(float16Ptr, base + 0)
            let v1 = f16ToFloat(float16Ptr, base + 1)
            let v2 = f16ToFloat(float16Ptr, base + 2)
            let v3 = f16ToFloat(float16Ptr, base + 3)

            let L: Float = -0.051509 * v0 + 0.039954 * v1 + 0.039893 * v2 - 0.087302 * v3 + 0.88591
            let a: Float = -0.028686 * v0 - 0.0061331 * v1 - 0.016837 * v2 + 0.016139 * v3 + 0.0018263
            let bLab: Float = -0.0068242 * v0 + 0.0068562 * v1 - 0.03415 * v2 + 0.00056286 * v3 + 0.0096209

            var (sr, sg, sb) = okLabToLinearSRGB(L: L, a: a, b: bLab)
            sr = linearSRGBToSRGB(sr) * 255
            sg = linearSRGBToSRGB(sg) * 255
            sb = linearSRGBToSRGB(sb) * 255

            uint8Ptr[i * 3 + 0] = UInt8(clamping: Int(sr.isFinite ? sr : 0))
            uint8Ptr[i * 3 + 1] = UInt8(clamping: Int(sg.isFinite ? sg : 0))
            uint8Ptr[i * 3 + 2] = UInt8(clamping: Int(sb.isFinite ? sb : 0))
        }
    }

    /// Convert OKLab to linear sRGB. Ports the upstream `OKlabToLinearsRGB`.
    @inline(__always)
    static func okLabToLinearSRGB(L: Float, a: Float, b: Float) -> (Float, Float, Float) {
        let l_ = L + 0.3963377774 * a + 0.2158037573 * b
        let m_ = L - 0.1055613458 * a - 0.0638541728 * b
        let s_ = L - 0.0894841775 * a - 1.2914855480 * b
        let l = l_ * l_ * l_
        let m = m_ * m_ * m_
        let s = s_ * s_ * s_
        return (
            +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        )
    }

    /// Convert linear sRGB to sRGB. Ports the upstream `linearsRGBTosRGB`.
    @inline(__always)
    static func linearSRGBToSRGB(_ x: Float) -> Float {
        if x >= 0.04045 {
            return pow((x + 0.055) / (1 + 0.055), 2.4)
        } else {
            return x / 12.92
        }
    }

    /// Convert a HiDream-O1 patch-packed latent into an RGB image.
    ///
    /// HiDream-O1 packs each 32×32 output patch into the channel dimension
    /// (channels = 3 × 32 × 32 = 3072), so the decoded image is 32× larger per side.
    /// Ports the upstream patch-unpacking preview path.
    static func hiDreamO1PatchToCGImage(_ tensorData: Data, imageWidth: Int, imageHeight: Int, channels: Int) throws -> CGImage {
        let patchSize = 32
        guard channels == 3 * patchSize * patchSize else {
            DTLogger.error("hiDreamO1PatchToImage: unexpected channel count \(channels), expected \(3 * patchSize * patchSize)", category: .images)
            throw ImageError.conversionFailed
        }

        let pixelDataOffset = 68
        let expectedDataSize = pixelDataOffset + (imageWidth * imageHeight * channels * 2)
        guard tensorData.count >= expectedDataSize else {
            throw ImageError.invalidData
        }

        let outputWidth = imageWidth * patchSize
        let outputHeight = imageHeight * patchSize
        let patchArea = patchSize * patchSize
        var rgbData = Data(count: outputWidth * outputHeight * 3)

        tensorData.withUnsafeBytes { (rawPtr: UnsafeRawBufferPointer) in
            let basePtr = rawPtr.baseAddress!.advanced(by: pixelDataOffset)
            let fp16 = basePtr.assumingMemoryBound(to: UInt16.self)

            rgbData.withUnsafeMutableBytes { (outPtr: UnsafeMutableRawBufferPointer) in
                let out = outPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)

                for y in 0..<outputHeight {
                    let patchY = y / patchSize
                    let patchYOffset = y % patchSize
                    for x in 0..<outputWidth {
                        let patchX = x / patchSize
                        let patchXOffset = x % patchSize
                        let patchPixelOffset = patchYOffset * patchSize + patchXOffset
                        let patchOffset = (patchY * imageWidth + patchX) * channels + patchPixelOffset

                        let rF = (f16ToFloat(fp16, patchOffset) + 1) * 127.5
                        let gF = (f16ToFloat(fp16, patchOffset + patchArea) + 1) * 127.5
                        let bF = (f16ToFloat(fp16, patchOffset + patchArea * 2) + 1) * 127.5

                        let o = (y * outputWidth + x) * 3
                        out[o + 0] = UInt8(clamping: Int(rF.isFinite ? rF : 0))
                        out[o + 1] = UInt8(clamping: Int(gF.isFinite ? gF : 0))
                        out[o + 2] = UInt8(clamping: Int(bF.isFinite ? bF : 0))
                    }
                }
            }
        }

        DTLogger.debug("hiDreamO1PatchToImage: decoded \(imageWidth)x\(imageHeight) patches -> \(outputWidth)x\(outputHeight) image", category: .images)
        return try makeRGBCGImage(rgbData, width: outputWidth, height: outputHeight)
    }

    /// Convert 3-channel RGB from [-1, 1] to [0, 255] (NHWC / interleaved layout)
    static func convert3ChannelToRGB(float16Ptr: UnsafePointer<UInt16>, uint8Ptr: UnsafeMutablePointer<UInt8>, pixelCount: Int) {
        for i in 0..<pixelCount {
            let floatValue = f16ToFloat(float16Ptr, i)
            let uint8Value = UInt8(clamping: Int(floatValue.isFinite ? (floatValue + 1.0) * 127.5 : 127.5))
            uint8Ptr[i] = uint8Value
        }
    }

    /// Convert 3-channel RGB from [-1, 1] to [0, 255] (NCHW / planar layout)
    /// Planar data is stored as [R0..RN, G0..GN, B0..BN] and must be interleaved to [R0,G0,B0, R1,G1,B1, ...]
    static func convert3ChannelNCHWToRGB(float16Ptr: UnsafePointer<UInt16>, uint8Ptr: UnsafeMutablePointer<UInt8>, width: Int, height: Int) {
        let pixelCount = width * height
        for i in 0..<pixelCount {
            let rVal = f16ToFloat(float16Ptr, i)
            let gVal = f16ToFloat(float16Ptr, pixelCount + i)
            let bVal = f16ToFloat(float16Ptr, 2 * pixelCount + i)
            uint8Ptr[i * 3]     = UInt8(clamping: Int(rVal.isFinite ? (rVal + 1.0) * 127.5 : 127.5))
            uint8Ptr[i * 3 + 1] = UInt8(clamping: Int(gVal.isFinite ? (gVal + 1.0) * 127.5 : 127.5))
            uint8Ptr[i * 3 + 2] = UInt8(clamping: Int(bVal.isFinite ? (bVal + 1.0) * 127.5 : 127.5))
        }
    }

    /// Convert 16-channel Flux latent to RGB
    static func convertFluxToRGB(float16Ptr: UnsafePointer<UInt16>, uint8Ptr: UnsafeMutablePointer<UInt8>, pixelCount: Int) {
        for i in 0..<pixelCount {
            let base = i * 16
            let v0 = f16ToFloat(float16Ptr, base + 0)
            let v1 = f16ToFloat(float16Ptr, base + 1)
            let v2 = f16ToFloat(float16Ptr, base + 2)
            let v3 = f16ToFloat(float16Ptr, base + 3)
            let v4 = f16ToFloat(float16Ptr, base + 4)
            let v5 = f16ToFloat(float16Ptr, base + 5)
            let v6 = f16ToFloat(float16Ptr, base + 6)
            let v7 = f16ToFloat(float16Ptr, base + 7)
            let v8 = f16ToFloat(float16Ptr, base + 8)
            let v9 = f16ToFloat(float16Ptr, base + 9)
            let v10 = f16ToFloat(float16Ptr, base + 10)
            let v11 = f16ToFloat(float16Ptr, base + 11)
            let v12 = f16ToFloat(float16Ptr, base + 12)
            let v13 = f16ToFloat(float16Ptr, base + 13)
            let v14 = f16ToFloat(float16Ptr, base + 14)
            let v15 = f16ToFloat(float16Ptr, base + 15)

            var rVal: Float = -0.0346 * v0 + 0.0034 * v1 + 0.0275 * v2 - 0.0174 * v3
            rVal += 0.0859 * v4 + 0.0004 * v5 + 0.0405 * v6 - 0.0236 * v7
            rVal += -0.0245 * v8 + 0.1008 * v9 - 0.0515 * v10 + 0.0428 * v11
            rVal += 0.0817 * v12 - 0.1264 * v13 - 0.0280 * v14 - 0.1262 * v15 - 0.0329
            let r = rVal * 127.5 + 127.5

            var gVal: Float = 0.0244 * v0 + 0.0210 * v1 - 0.0668 * v2 + 0.0160 * v3
            gVal += 0.0721 * v4 + 0.0383 * v5 + 0.0861 * v6 - 0.0185 * v7
            gVal += 0.0250 * v8 + 0.0755 * v9 + 0.0201 * v10 - 0.0012 * v11
            gVal += 0.0765 * v12 - 0.0522 * v13 - 0.0881 * v14 - 0.0982 * v15 - 0.0718
            let g = gVal * 127.5 + 127.5

            var bVal: Float = 0.0681 * v0 + 0.0687 * v1 - 0.0433 * v2 + 0.0617 * v3
            bVal += 0.0329 * v4 + 0.0115 * v5 + 0.0915 * v6 - 0.0259 * v7
            bVal += 0.1180 * v8 - 0.0421 * v9 + 0.0011 * v10 - 0.0036 * v11
            bVal += 0.0749 * v12 - 0.1103 * v13 - 0.0499 * v14 - 0.0778 * v15 - 0.0851
            let b = bVal * 127.5 + 127.5

            uint8Ptr[i * 3 + 0] = UInt8(clamping: Int(r.isFinite ? r : 0))
            uint8Ptr[i * 3 + 1] = UInt8(clamping: Int(g.isFinite ? g : 0))
            uint8Ptr[i * 3 + 2] = UInt8(clamping: Int(b.isFinite ? b : 0))
        }
    }

    /// Convert 16-channel SD3 latent to RGB
    static func convertSD3ToRGB(float16Ptr: UnsafePointer<UInt16>, uint8Ptr: UnsafeMutablePointer<UInt8>, pixelCount: Int) {
        for i in 0..<pixelCount {
            let base = i * 16
            let v0 = f16ToFloat(float16Ptr, base + 0)
            let v1 = f16ToFloat(float16Ptr, base + 1)
            let v2 = f16ToFloat(float16Ptr, base + 2)
            let v3 = f16ToFloat(float16Ptr, base + 3)
            let v4 = f16ToFloat(float16Ptr, base + 4)
            let v5 = f16ToFloat(float16Ptr, base + 5)
            let v6 = f16ToFloat(float16Ptr, base + 6)
            let v7 = f16ToFloat(float16Ptr, base + 7)
            let v8 = f16ToFloat(float16Ptr, base + 8)
            let v9 = f16ToFloat(float16Ptr, base + 9)
            let v10 = f16ToFloat(float16Ptr, base + 10)
            let v11 = f16ToFloat(float16Ptr, base + 11)
            let v12 = f16ToFloat(float16Ptr, base + 12)
            let v13 = f16ToFloat(float16Ptr, base + 13)
            let v14 = f16ToFloat(float16Ptr, base + 14)
            let v15 = f16ToFloat(float16Ptr, base + 15)

            var rVal: Float = -0.0922 * v0 + 0.0311 * v1 + 0.1994 * v2 + 0.0856 * v3
            rVal += 0.0587 * v4 - 0.0006 * v5 + 0.0978 * v6 - 0.0042 * v7
            rVal += -0.0194 * v8 - 0.0488 * v9 + 0.0922 * v10 - 0.0278 * v11
            rVal += 0.0332 * v12 - 0.0069 * v13 - 0.0596 * v14 - 0.1448 * v15 + 0.2394
            let r = rVal * 127.5 + 127.5

            var gVal: Float = -0.0175 * v0 + 0.0633 * v1 + 0.0927 * v2 + 0.0339 * v3
            gVal += 0.0272 * v4 + 0.1104 * v5 + 0.0306 * v6 + 0.1038 * v7
            gVal += 0.0020 * v8 + 0.0130 * v9 + 0.0988 * v10 + 0.0524 * v11
            gVal += 0.0456 * v12 - 0.0030 * v13 - 0.0465 * v14 - 0.1463 * v15 + 0.2135
            let g = gVal * 127.5 + 127.5

            var bVal: Float = 0.0749 * v0 + 0.0954 * v1 + 0.0458 * v2 + 0.0902 * v3
            bVal += -0.0496 * v4 + 0.0309 * v5 + 0.0427 * v6 + 0.1358 * v7
            bVal += 0.0669 * v8 - 0.0268 * v9 + 0.0951 * v10 - 0.0542 * v11
            bVal += 0.0895 * v12 - 0.0810 * v13 - 0.0293 * v14 - 0.1189 * v15 + 0.1925
            let b = bVal * 127.5 + 127.5

            uint8Ptr[i * 3 + 0] = UInt8(clamping: Int(r.isFinite ? r : 0))
            uint8Ptr[i * 3 + 1] = UInt8(clamping: Int(g.isFinite ? g : 0))
            uint8Ptr[i * 3 + 2] = UInt8(clamping: Int(b.isFinite ? b : 0))
        }
    }

    /// Convert 16-channel HunyuanVideo latent to RGB
    static func convertHunyuanVideoToRGB(float16Ptr: UnsafePointer<UInt16>, uint8Ptr: UnsafeMutablePointer<UInt8>, pixelCount: Int) {
        for i in 0..<pixelCount {
            let base = i * 16
            let v0 = f16ToFloat(float16Ptr, base + 0)
            let v1 = f16ToFloat(float16Ptr, base + 1)
            let v2 = f16ToFloat(float16Ptr, base + 2)
            let v3 = f16ToFloat(float16Ptr, base + 3)
            let v4 = f16ToFloat(float16Ptr, base + 4)
            let v5 = f16ToFloat(float16Ptr, base + 5)
            let v6 = f16ToFloat(float16Ptr, base + 6)
            let v7 = f16ToFloat(float16Ptr, base + 7)
            let v8 = f16ToFloat(float16Ptr, base + 8)
            let v9 = f16ToFloat(float16Ptr, base + 9)
            let v10 = f16ToFloat(float16Ptr, base + 10)
            let v11 = f16ToFloat(float16Ptr, base + 11)
            let v12 = f16ToFloat(float16Ptr, base + 12)
            let v13 = f16ToFloat(float16Ptr, base + 13)
            let v14 = f16ToFloat(float16Ptr, base + 14)
            let v15 = f16ToFloat(float16Ptr, base + 15)

            var rVal: Float = -0.0395 * v0 + 0.0696 * v1 + 0.0135 * v2 + 0.0108 * v3
            rVal += -0.0209 * v4 - 0.0804 * v5 - 0.0991 * v6 - 0.0646 * v7
            rVal += -0.0696 * v8 - 0.0799 * v9 + 0.1166 * v10 + 0.1165 * v11
            rVal += -0.2315 * v12 - 0.0270 * v13 - 0.0616 * v14 + 0.0249 * v15 + 0.0249
            let r = rVal * 127.5 + 127.5

            var gVal: Float = -0.0331 * v0 + 0.0795 * v1 - 0.0945 * v2 - 0.0250 * v3
            gVal += 0.0032 * v4 - 0.0254 * v5 + 0.0271 * v6 - 0.0422 * v7
            gVal += -0.0595 * v8 - 0.0208 * v9 + 0.1627 * v10 + 0.0432 * v11
            gVal += -0.1920 * v12 + 0.0401 * v13 - 0.0997 * v14 - 0.0469 * v15 - 0.0192
            let g = gVal * 127.5 + 127.5

            var bVal: Float = 0.0445 * v0 + 0.0518 * v1 - 0.0282 * v2 - 0.0765 * v3
            bVal += 0.0224 * v4 - 0.0639 * v5 - 0.0669 * v6 - 0.0400 * v7
            bVal += -0.0894 * v8 - 0.0375 * v9 + 0.0962 * v10 + 0.0407 * v11
            bVal += -0.1355 * v12 - 0.0821 * v13 - 0.0727 * v14 - 0.1703 * v15 - 0.0761
            let b = bVal * 127.5 + 127.5

            uint8Ptr[i * 3 + 0] = UInt8(clamping: Int(r.isFinite ? r : 0))
            uint8Ptr[i * 3 + 1] = UInt8(clamping: Int(g.isFinite ? g : 0))
            uint8Ptr[i * 3 + 2] = UInt8(clamping: Int(b.isFinite ? b : 0))
        }
    }

    /// Convert 16-channel Qwen/Wan 2.1 latent to RGB
    static func convertQwenWan21ToRGB(float16Ptr: UnsafePointer<UInt16>, uint8Ptr: UnsafeMutablePointer<UInt8>, pixelCount: Int) {
        for i in 0..<pixelCount {
            let base = i * 16
            let v0 = f16ToFloat(float16Ptr, base + 0)
            let v1 = f16ToFloat(float16Ptr, base + 1)
            let v2 = f16ToFloat(float16Ptr, base + 2)
            let v3 = f16ToFloat(float16Ptr, base + 3)
            let v4 = f16ToFloat(float16Ptr, base + 4)
            let v5 = f16ToFloat(float16Ptr, base + 5)
            let v6 = f16ToFloat(float16Ptr, base + 6)
            let v7 = f16ToFloat(float16Ptr, base + 7)
            let v8 = f16ToFloat(float16Ptr, base + 8)
            let v9 = f16ToFloat(float16Ptr, base + 9)
            let v10 = f16ToFloat(float16Ptr, base + 10)
            let v11 = f16ToFloat(float16Ptr, base + 11)
            let v12 = f16ToFloat(float16Ptr, base + 12)
            let v13 = f16ToFloat(float16Ptr, base + 13)
            let v14 = f16ToFloat(float16Ptr, base + 14)
            let v15 = f16ToFloat(float16Ptr, base + 15)

            var rVal: Float = -0.1299 * v0 + 0.0671 * v1 + 0.3568 * v2 + 0.0372 * v3
            rVal += 0.0313 * v4 + 0.0296 * v5 - 0.3477 * v6 + 0.0166 * v7
            rVal += -0.0412 * v8 - 0.1293 * v9 + 0.0680 * v10 + 0.0032 * v11
            rVal += -0.1251 * v12 + 0.0060 * v13 + 0.3477 * v14 + 0.1984 * v15 - 0.1835
            let r = rVal * 127.5 + 127.5

            var gVal: Float = -0.1692 * v0 + 0.0406 * v1 + 0.2548 * v2 + 0.2344 * v3
            gVal += 0.0189 * v4 - 0.0956 * v5 - 0.4059 * v6 + 0.1902 * v7
            gVal += 0.0267 * v8 + 0.0740 * v9 + 0.3019 * v10 + 0.0581 * v11
            gVal += 0.0927 * v12 - 0.0633 * v13 + 0.2275 * v14 + 0.0913 * v15 - 0.0868
            let g = gVal * 127.5 + 127.5

            var bVal: Float = 0.2932 * v0 + 0.0442 * v1 + 0.1747 * v2 + 0.1420 * v3
            bVal += -0.0328 * v4 - 0.0665 * v5 - 0.2925 * v6 + 0.1975 * v7
            bVal += -0.1364 * v8 + 0.1636 * v9 + 0.1128 * v10 + 0.0639 * v11
            bVal += 0.1699 * v12 + 0.0005 * v13 + 0.2950 * v14 + 0.1861 * v15 - 0.336
            let b = bVal * 127.5 + 127.5

            uint8Ptr[i * 3 + 0] = UInt8(clamping: Int(r.isFinite ? r : 0))
            uint8Ptr[i * 3 + 1] = UInt8(clamping: Int(g.isFinite ? g : 0))
            uint8Ptr[i * 3 + 2] = UInt8(clamping: Int(b.isFinite ? b : 0))
        }
    }

    // Qwen Image 2.1 latent-to-RGB coefficients (ComfyUI comfy/latent_formats.py: QwenImage21,
    // mirrored from upstream ImageConverter), applied to normalized latents.
    private static let qwen21RCoefficients: [Float] = [
        -0.0158, 0.0030, 0.0637, 0.0360, 0.0159, 0.0132, 0.0191, -0.0146,
        0.0187, -0.1059, -0.0195, -0.0295, 0.0191, -0.0144, 0.0389, -0.0153,
        0.0339, -0.0136, -0.0340, -0.0133, 0.0109, -0.0010, 0.0301, -0.0281,
        -0.0725, -0.0036, 0.0087, -0.0260, -0.0039, -0.0026, 0.0088, -0.0087,
        -0.0027, -0.0064, 0.0594, 0.0103, -0.0091, 0.0178, -0.0063, 0.0452,
        0.0149, 0.1484, -0.0120, 0.0181, 0.0132, 0.0291, 0.0066, -0.1153,
        0.0258, 0.0375, -0.0142, 0.0339, 0.0346, 0.0369, -0.0052, -0.0279,
        0.0036, -0.0441, -0.0001, -0.0222, 0.0039, -0.0094, -0.0066, 0.0220
    ]
    private static let qwen21GCoefficients: [Float] = [
        -0.0115, 0.0120, 0.0470, 0.0661, 0.0181, 0.0326, 0.0261, -0.0276,
        -0.0024, -0.0090, -0.0226, 0.0024, -0.0393, -0.0166, 0.0430, -0.0336,
        0.0122, -0.0078, -0.0282, -0.0176, -0.0087, 0.0044, 0.0053, -0.0205,
        0.0002, 0.0158, 0.0040, 0.0183, -0.0035, 0.0172, 0.0078, -0.0310,
        0.0018, 0.0292, 0.1049, -0.0103, 0.0025, 0.0243, -0.0012, 0.0246,
        0.0270, 0.0801, 0.0040, 0.0051, 0.0050, 0.0020, -0.0410, -0.0629,
        0.0378, 0.1139, -0.0126, 0.0153, 0.0211, -0.0431, -0.0092, 0.0410,
        0.0017, -0.0367, -0.0092, -0.0183, 0.0053, -0.0075, -0.0088, 0.0074
    ]
    private static let qwen21BCoefficients: [Float] = [
        -0.0174, 0.0027, -0.0127, -0.0030, 0.0082, 0.0169, 0.0136, -0.0361,
        -0.0072, 0.0350, -0.0138, -0.0215, -0.0001, -0.0272, 0.0445, 0.0031,
        0.0220, -0.0120, -0.0245, -0.0133, 0.0096, 0.0016, 0.0361, -0.0032,
        0.0160, 0.0807, -0.0053, -0.0077, -0.0107, 0.0237, 0.0078, -0.0122,
        0.0094, -0.0256, 0.1180, -0.0026, -0.0015, 0.0292, 0.0202, 0.0143,
        0.0052, 0.0804, 0.0010, -0.0021, 0.0019, 0.0092, -0.1314, -0.0802,
        0.0298, 0.0468, -0.0276, 0.0138, 0.0267, -0.0993, 0.0056, -0.0357,
        -0.0083, -0.0454, -0.0001, -0.0051, -0.0184, -0.0143, -0.0063, 0.0100
    ]

    /// Convert 64-channel Qwen Image 2.1 latent to RGB
    static func convertQwen21ToRGB(float16Ptr: UnsafePointer<UInt16>, uint8Ptr: UnsafeMutablePointer<UInt8>, pixelCount: Int) {
        for i in 0..<pixelCount {
            let base = i * 64
            var rVal: Float = -0.1228
            var gVal: Float = -0.1869
            var bVal: Float = -0.3083
            for c in 0..<64 {
                let v = f16ToFloat(float16Ptr, base + c)
                rVal += qwen21RCoefficients[c] * v
                gVal += qwen21GCoefficients[c] * v
                bVal += qwen21BCoefficients[c] * v
            }
            let r = rVal * 127.5 + 127.5
            let g = gVal * 127.5 + 127.5
            let b = bVal * 127.5 + 127.5

            uint8Ptr[i * 3 + 0] = UInt8(clamping: Int(r.isFinite ? r : 0))
            uint8Ptr[i * 3 + 1] = UInt8(clamping: Int(g.isFinite ? g : 0))
            uint8Ptr[i * 3 + 2] = UInt8(clamping: Int(b.isFinite ? b : 0))
        }
    }

    /// Convert 32-channel Flux 2 latent to RGB
    static func convertFlux2ToRGB(float16Ptr: UnsafePointer<UInt16>, uint8Ptr: UnsafeMutablePointer<UInt8>, pixelCount: Int) {
        for i in 0..<pixelCount {
            let base = i * 32
            let v0 = f16ToFloat(float16Ptr, base + 0)
            let v1 = f16ToFloat(float16Ptr, base + 1)
            let v2 = f16ToFloat(float16Ptr, base + 2)
            let v3 = f16ToFloat(float16Ptr, base + 3)
            let v4 = f16ToFloat(float16Ptr, base + 4)
            let v5 = f16ToFloat(float16Ptr, base + 5)
            let v6 = f16ToFloat(float16Ptr, base + 6)
            let v7 = f16ToFloat(float16Ptr, base + 7)
            let v8 = f16ToFloat(float16Ptr, base + 8)
            let v9 = f16ToFloat(float16Ptr, base + 9)
            let v10 = f16ToFloat(float16Ptr, base + 10)
            let v11 = f16ToFloat(float16Ptr, base + 11)
            let v12 = f16ToFloat(float16Ptr, base + 12)
            let v13 = f16ToFloat(float16Ptr, base + 13)
            let v14 = f16ToFloat(float16Ptr, base + 14)
            let v15 = f16ToFloat(float16Ptr, base + 15)
            let v16 = f16ToFloat(float16Ptr, base + 16)
            let v17 = f16ToFloat(float16Ptr, base + 17)
            let v18 = f16ToFloat(float16Ptr, base + 18)
            let v19 = f16ToFloat(float16Ptr, base + 19)
            let v20 = f16ToFloat(float16Ptr, base + 20)
            let v21 = f16ToFloat(float16Ptr, base + 21)
            let v22 = f16ToFloat(float16Ptr, base + 22)
            let v23 = f16ToFloat(float16Ptr, base + 23)
            let v24 = f16ToFloat(float16Ptr, base + 24)
            let v25 = f16ToFloat(float16Ptr, base + 25)
            let v26 = f16ToFloat(float16Ptr, base + 26)
            let v27 = f16ToFloat(float16Ptr, base + 27)
            let v28 = f16ToFloat(float16Ptr, base + 28)
            let v29 = f16ToFloat(float16Ptr, base + 29)
            let v30 = f16ToFloat(float16Ptr, base + 30)
            let v31 = f16ToFloat(float16Ptr, base + 31)

            // Flux 2 coefficients
            var rVal: Float = 0.0058 * v0 + 0.0495 * v1 - 0.0099 * v2 + 0.2144 * v3
            rVal += 0.0166 * v4 + 0.0157 * v5 - 0.0398 * v6 - 0.0052 * v7
            rVal += -0.3527 * v8 - 0.0301 * v9 - 0.0107 * v10 + 0.0746 * v11
            rVal += 0.0156 * v12 - 0.0034 * v13 + 0.0032 * v14 - 0.0939 * v15
            rVal += 0.0018 * v16 + 0.0284 * v17 - 0.0024 * v18 + 0.1207 * v19
            rVal += 0.0128 * v20 + 0.0137 * v21 + 0.0095 * v22 + 0.0000 * v23
            rVal += -0.0465 * v24 + 0.0095 * v25 + 0.0290 * v26 + 0.0220 * v27
            rVal += -0.0332 * v28 - 0.0085 * v29 - 0.0076 * v30 - 0.0111 * v31 - 0.0329
            let r = rVal * 127.5 + 127.5

            var gVal: Float = 0.0113 * v0 + 0.0443 * v1 + 0.0096 * v2 + 0.3009 * v3
            gVal += -0.0039 * v4 + 0.0103 * v5 + 0.0902 * v6 + 0.0095 * v7
            gVal += -0.2712 * v8 - 0.0356 * v9 + 0.0078 * v10 + 0.0090 * v11
            gVal += 0.0169 * v12 - 0.0040 * v13 + 0.0181 * v14 - 0.0008 * v15
            gVal += 0.0043 * v16 + 0.0056 * v17 - 0.0022 * v18 - 0.0026 * v19
            gVal += 0.0101 * v20 - 0.0072 * v21 + 0.0092 * v22 - 0.0077 * v23
            gVal += -0.0204 * v24 + 0.0012 * v25 - 0.0034 * v26 + 0.0169 * v27
            gVal += -0.0457 * v28 + 0.0389 * v29 + 0.0003 * v30 - 0.0460 * v31 - 0.0718
            let g = gVal * 127.5 + 127.5

            var bVal: Float = 0.0073 * v0 + 0.0836 * v1 + 0.0644 * v2 + 0.3652 * v3
            bVal += -0.0054 * v4 - 0.0160 * v5 - 0.0235 * v6 + 0.0109 * v7
            bVal += -0.1666 * v8 - 0.0180 * v9 + 0.0013 * v10 - 0.0941 * v11
            bVal += 0.0070 * v12 - 0.0114 * v13 + 0.0080 * v14 + 0.0186 * v15
            bVal += 0.0104 * v16 - 0.0127 * v17 - 0.0030 * v18 + 0.0065 * v19
            bVal += 0.0142 * v20 - 0.0007 * v21 - 0.0059 * v22 - 0.0049 * v23
            bVal += -0.0312 * v24 - 0.0066 * v25 + 0.0025 * v26 - 0.0048 * v27
            bVal += -0.0468 * v28 + 0.0609 * v29 - 0.0043 * v30 - 0.0614 * v31 - 0.0851
            let b = bVal * 127.5 + 127.5

            uint8Ptr[i * 3 + 0] = UInt8(clamping: Int(r.isFinite ? r : 0))
            uint8Ptr[i * 3 + 1] = UInt8(clamping: Int(g.isFinite ? g : 0))
            uint8Ptr[i * 3 + 2] = UInt8(clamping: Int(b.isFinite ? b : 0))
        }
    }

    /// Convert 24-channel MiniMax H3 latent to RGB (upstream preview coefficients)
    static func convertMiniMaxH3ToRGB(float16Ptr: UnsafePointer<UInt16>, uint8Ptr: UnsafeMutablePointer<UInt8>, pixelCount: Int) {
        for i in 0..<pixelCount {
            let base = i * 24
            let v0 = f16ToFloat(float16Ptr, base + 0)
            let v1 = f16ToFloat(float16Ptr, base + 1)
            let v2 = f16ToFloat(float16Ptr, base + 2)
            let v3 = f16ToFloat(float16Ptr, base + 3)
            let v4 = f16ToFloat(float16Ptr, base + 4)
            let v5 = f16ToFloat(float16Ptr, base + 5)
            let v6 = f16ToFloat(float16Ptr, base + 6)
            let v7 = f16ToFloat(float16Ptr, base + 7)
            let v8 = f16ToFloat(float16Ptr, base + 8)
            let v9 = f16ToFloat(float16Ptr, base + 9)
            let v10 = f16ToFloat(float16Ptr, base + 10)
            let v11 = f16ToFloat(float16Ptr, base + 11)
            let v12 = f16ToFloat(float16Ptr, base + 12)
            let v13 = f16ToFloat(float16Ptr, base + 13)
            let v14 = f16ToFloat(float16Ptr, base + 14)
            let v15 = f16ToFloat(float16Ptr, base + 15)
            let v16 = f16ToFloat(float16Ptr, base + 16)
            let v17 = f16ToFloat(float16Ptr, base + 17)
            let v18 = f16ToFloat(float16Ptr, base + 18)
            let v19 = f16ToFloat(float16Ptr, base + 19)
            let v20 = f16ToFloat(float16Ptr, base + 20)
            let v21 = f16ToFloat(float16Ptr, base + 21)
            let v22 = f16ToFloat(float16Ptr, base + 22)
            let v23 = f16ToFloat(float16Ptr, base + 23)

            var rVal: Float = -0.018555 * v0 + 0.150164 * v1 + 0.027367 * v2 - 0.000793 * v3
            rVal += -0.048556 * v4 + 0.011740 * v5 + 0.061517 * v6 + 0.035321 * v7
            rVal += -0.017426 * v8 + 0.531539 * v9 - 0.024968 * v10 - 0.032549 * v11
            rVal += 0.022609 * v12 - 0.084001 * v13 - 0.018830 * v14 + 0.020777 * v15
            rVal += -0.008390 * v16 - 0.013281 * v17 + 0.000260 * v18 + 0.105471 * v19
            rVal += 0.016529 * v20 - 0.014015 * v21 - 0.033787 * v22 + 0.004224 * v23
            rVal += 0.057426
            let r = rVal * 127.5 + 127.5

            var gVal: Float = 0.024344 * v0 + 0.137244 * v1 - 0.050369 * v2 - 0.164622 * v3
            gVal += 0.013970 * v4 + 0.014172 * v5 + 0.061212 * v6 + 0.086879 * v7
            gVal += 0.002997 * v8 + 0.548819 * v9 - 0.040234 * v10 - 0.029096 * v11
            gVal += 0.020286 * v12 - 0.038131 * v13 + 0.010412 * v14 + 0.011196 * v15
            gVal += -0.012201 * v16 - 0.002924 * v17 + 0.001833 * v18 + 0.100482 * v19
            gVal += 0.015213 * v20 - 0.017438 * v21 - 0.009984 * v22 + 0.017284 * v23
            gVal += -0.022078
            let g = gVal * 127.5 + 127.5

            var bVal: Float = -0.017536 * v0 + 0.129221 * v1 - 0.208606 * v2 - 0.323161 * v3
            bVal += -0.074286 * v4 - 0.006906 * v5 + 0.110025 * v6 + 0.110059 * v7
            bVal += 0.035356 * v8 + 0.624404 * v9 - 0.034302 * v10 - 0.017221 * v11
            bVal += 0.050661 * v12 - 0.020805 * v13 + 0.061120 * v14 - 0.030994 * v15
            bVal += -0.025687 * v16 + 0.006331 * v17 - 0.011038 * v18 + 0.132106 * v19
            bVal += 0.009999 * v20 - 0.019134 * v21 - 0.019725 * v22 + 0.027196 * v23
            bVal += -0.071449
            let b = bVal * 127.5 + 127.5

            uint8Ptr[i * 3 + 0] = UInt8(clamping: Int(r.isFinite ? r : 0))
            uint8Ptr[i * 3 + 1] = UInt8(clamping: Int(g.isFinite ? g : 0))
            uint8Ptr[i * 3 + 2] = UInt8(clamping: Int(b.isFinite ? b : 0))
        }
    }

    /// Convert 48-channel Wan 2.2 5B latent to RGB
    static func convert48ChannelToRGB(float16Ptr: UnsafePointer<UInt16>, uint8Ptr: UnsafeMutablePointer<UInt8>, pixelCount: Int) {
        for i in 0..<pixelCount {
            // Read all 48 channels
            let base = i * 48
            let v0 = f16ToFloat(float16Ptr, base + 0)
            let v1 = f16ToFloat(float16Ptr, base + 1)
            let v2 = f16ToFloat(float16Ptr, base + 2)
            let v3 = f16ToFloat(float16Ptr, base + 3)
            let v4 = f16ToFloat(float16Ptr, base + 4)
            let v5 = f16ToFloat(float16Ptr, base + 5)
            let v6 = f16ToFloat(float16Ptr, base + 6)
            let v7 = f16ToFloat(float16Ptr, base + 7)
            let v8 = f16ToFloat(float16Ptr, base + 8)
            let v9 = f16ToFloat(float16Ptr, base + 9)
            let v10 = f16ToFloat(float16Ptr, base + 10)
            let v11 = f16ToFloat(float16Ptr, base + 11)
            let v12 = f16ToFloat(float16Ptr, base + 12)
            let v13 = f16ToFloat(float16Ptr, base + 13)
            let v14 = f16ToFloat(float16Ptr, base + 14)
            let v15 = f16ToFloat(float16Ptr, base + 15)
            let v16 = f16ToFloat(float16Ptr, base + 16)
            let v17 = f16ToFloat(float16Ptr, base + 17)
            let v18 = f16ToFloat(float16Ptr, base + 18)
            let v19 = f16ToFloat(float16Ptr, base + 19)
            let v20 = f16ToFloat(float16Ptr, base + 20)
            let v21 = f16ToFloat(float16Ptr, base + 21)
            let v22 = f16ToFloat(float16Ptr, base + 22)
            let v23 = f16ToFloat(float16Ptr, base + 23)
            let v24 = f16ToFloat(float16Ptr, base + 24)
            let v25 = f16ToFloat(float16Ptr, base + 25)
            let v26 = f16ToFloat(float16Ptr, base + 26)
            let v27 = f16ToFloat(float16Ptr, base + 27)
            let v28 = f16ToFloat(float16Ptr, base + 28)
            let v29 = f16ToFloat(float16Ptr, base + 29)
            let v30 = f16ToFloat(float16Ptr, base + 30)
            let v31 = f16ToFloat(float16Ptr, base + 31)
            let v32 = f16ToFloat(float16Ptr, base + 32)
            let v33 = f16ToFloat(float16Ptr, base + 33)
            let v34 = f16ToFloat(float16Ptr, base + 34)
            let v35 = f16ToFloat(float16Ptr, base + 35)
            let v36 = f16ToFloat(float16Ptr, base + 36)
            let v37 = f16ToFloat(float16Ptr, base + 37)
            let v38 = f16ToFloat(float16Ptr, base + 38)
            let v39 = f16ToFloat(float16Ptr, base + 39)
            let v40 = f16ToFloat(float16Ptr, base + 40)
            let v41 = f16ToFloat(float16Ptr, base + 41)
            let v42 = f16ToFloat(float16Ptr, base + 42)
            let v43 = f16ToFloat(float16Ptr, base + 43)
            let v44 = f16ToFloat(float16Ptr, base + 44)
            let v45 = f16ToFloat(float16Ptr, base + 45)
            let v46 = f16ToFloat(float16Ptr, base + 46)
            let v47 = f16ToFloat(float16Ptr, base + 47)

            // Wan 2.2 5B coefficients
            var rVal: Float = 0.0119 * v0 - 0.1062 * v1 + 0.0140 * v2 - 0.0813 * v3
            rVal += 0.0656 * v4 + 0.0264 * v5 + 0.0295 * v6 - 0.0244 * v7
            rVal += 0.0443 * v8 - 0.0465 * v9 + 0.0359 * v10 - 0.0776 * v11
            rVal += 0.0564 * v12 + 0.0006 * v13 - 0.0319 * v14 - 0.0268 * v15
            rVal += 0.0539 * v16 - 0.0359 * v17 - 0.0285 * v18 + 0.1041 * v19
            rVal += -0.0086 * v20 + 0.0390 * v21 + 0.0069 * v22 + 0.0006 * v23
            rVal += 0.0313 * v24 - 0.1454 * v25 + 0.0714 * v26 - 0.0304 * v27
            rVal += 0.0401 * v28 - 0.0758 * v29 + 0.0568 * v30 - 0.0055 * v31
            rVal += 0.0239 * v32 - 0.0663 * v33 - 0.0416 * v34 + 0.0166 * v35
            rVal += -0.0211 * v36 + 0.1833 * v37 - 0.0368 * v38 - 0.3441 * v39
            rVal += -0.0479 * v40 - 0.0660 * v41 - 0.0101 * v42 - 0.0690 * v43
            rVal += -0.0145 * v44 + 0.0421 * v45 + 0.0504 * v46 - 0.0837 * v47
            let r = rVal * 127.5 + 127.5

            var gVal: Float = 0.0103 * v0 - 0.0504 * v1 + 0.0409 * v2 - 0.0677 * v3
            gVal += 0.0851 * v4 + 0.0463 * v5 + 0.0326 * v6 - 0.0270 * v7
            gVal += -0.0102 * v8 - 0.0090 * v9 + 0.0236 * v10 + 0.0854 * v11
            gVal += 0.0264 * v12 + 0.0594 * v13 - 0.0542 * v14 + 0.0024 * v15
            gVal += 0.0265 * v16 - 0.0312 * v17 - 0.1032 * v18 + 0.0537 * v19
            gVal += -0.0374 * v20 + 0.0670 * v21 + 0.0144 * v22 - 0.0167 * v23
            gVal += -0.0574 * v24 - 0.0902 * v25 + 0.0827 * v26 - 0.0574 * v27
            gVal += 0.0384 * v28 - 0.0297 * v29 + 0.1307 * v30 - 0.0310 * v31
            gVal += -0.0305 * v32 - 0.0673 * v33 - 0.0047 * v34 + 0.0112 * v35
            gVal += 0.0011 * v36 + 0.1466 * v37 + 0.0370 * v38 - 0.3543 * v39
            gVal += -0.0489 * v40 - 0.0153 * v41 + 0.0068 * v42 - 0.0452 * v43
            gVal += 0.0041 * v44 + 0.0451 * v45 - 0.0483 * v46 + 0.0168 * v47
            let g = gVal * 127.5 + 127.5

            var bVal: Float = 0.0046 * v0 + 0.0165 * v1 + 0.0491 * v2 + 0.0607 * v3
            bVal += 0.0808 * v4 + 0.0912 * v5 + 0.0590 * v6 + 0.0025 * v7
            bVal += 0.0288 * v8 - 0.0205 * v9 + 0.0082 * v10 + 0.1048 * v11
            bVal += 0.0561 * v12 + 0.0418 * v13 - 0.0637 * v14 + 0.0260 * v15
            bVal += 0.0358 * v16 - 0.0287 * v17 - 0.1237 * v18 + 0.0622 * v19
            bVal += -0.0051 * v20 + 0.2863 * v21 + 0.0082 * v22 + 0.0079 * v23
            bVal += -0.0232 * v24 - 0.0481 * v25 + 0.0447 * v26 - 0.0196 * v27
            bVal += 0.0204 * v28 - 0.0014 * v29 + 0.1372 * v30 - 0.0380 * v31
            bVal += 0.0325 * v32 - 0.0140 * v33 - 0.0023 * v34 - 0.0093 * v35
            bVal += 0.0331 * v36 + 0.2250 * v37 + 0.0295 * v38 - 0.2008 * v39
            bVal += -0.0420 * v40 + 0.0800 * v41 + 0.0156 * v42 - 0.0927 * v43
            bVal += 0.0015 * v44 + 0.0373 * v45 - 0.0356 * v46 + 0.0055 * v47
            let b = bVal * 127.5 + 127.5

            uint8Ptr[i * 3 + 0] = UInt8(clamping: Int(r.isFinite ? r : 0))
            uint8Ptr[i * 3 + 1] = UInt8(clamping: Int(g.isFinite ? g : 0))
            uint8Ptr[i * 3 + 2] = UInt8(clamping: Int(b.isFinite ? b : 0))
        }
    }

    /// Wraps packed 8-bit RGB pixels in a `CGImage`.
}
