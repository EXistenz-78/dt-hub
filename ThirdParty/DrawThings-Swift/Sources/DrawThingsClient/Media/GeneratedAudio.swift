//
//  GeneratedAudio.swift
//  DrawThingsClient
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import AVFoundation
import Foundation

/// Audio generated alongside a video (LTX-2, MiniMax H3, LongCat Avatar...), as planar
/// 32-bit float PCM in [-1, 1].
public struct GeneratedAudio: Sendable, Hashable {
    /// Samples for each channel; every channel has ``frameCount`` samples.
    public let channels: [[Float]]
    /// Samples per second.
    public let sampleRate: Double

    public init(channels: [[Float]], sampleRate: Double) {
        self.channels = channels
        self.sampleRate = sampleRate
    }

    public var channelCount: Int { channels.count }
    public var frameCount: Int { channels.first?.count ?? 0 }
    public var duration: TimeInterval { sampleRate > 0 ? Double(frameCount) / sampleRate : 0 }

    // MARK: - Decoding

    private static let headerSize = 68
    private static let ccv32F: UInt32 = 0x04000
    private static let formatNHWC: UInt32 = 0x02

    /// Decodes a CCV audio tensor (68-byte header followed by Float32 samples, optionally
    /// compressed). Generated audio carries no rate metadata, so pass the model's rate
    /// (``ModelFamily/audioSampleRate``).
    public init(tensor data: Data, sampleRate: Double) throws {
        let data = try TensorDecompression.decompressIfNeeded(data)
        guard data.count >= Self.headerSize else {
            throw AudioHelpers.AudioError.invalidData("data too small: \(data.count) bytes, need at least \(Self.headerSize)")
        }
        let header: [UInt32] = data.withUnsafeBytes { raw in
            (0..<17).map { raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self) }
        }
        let format = header[2]
        guard header[3] == Self.ccv32F else { throw AudioHelpers.AudioError.unsupportedDataType(header[3]) }

        // Audio tensors are either 2D [channels, samples] or image-like 4D [N, H, W, channels].
        let dims = header[5...8].map(Int.init)
        let channelCount: Int
        let samplesPerChannel: (Int, overflow: Bool)
        if dims[2] == 0 && dims[3] == 0 {
            channelCount = dims[0]
            samplesPerChannel = (dims[1], false)
        } else if dims[2] > 0 && dims[3] > 0 {
            channelCount = dims[3]
            samplesPerChannel = dims[1].multipliedReportingOverflow(by: dims[2])
        } else {
            channelCount = dims[0]
            samplesPerChannel = dims[1].multipliedReportingOverflow(by: max(dims[2], 1))
        }
        let frames = samplesPerChannel.0
        let total = channelCount.multipliedReportingOverflow(by: frames)
        let bytes = total.partialValue.multipliedReportingOverflow(by: MemoryLayout<Float>.size)
        guard !samplesPerChannel.overflow, !total.overflow, !bytes.overflow,
              channelCount > 0, channelCount <= 64, frames > 0,
              data.count >= Self.headerSize + bytes.partialValue
        else {
            throw AudioHelpers.AudioError.invalidData(
                "invalid dimensions \(dims) for \(data.count) bytes (format 0x\(String(format, radix: 16)))")
        }

        let interleaved = (format & Self.formatNHWC) != 0
        self.channels = data.withUnsafeBytes { raw in
            let base = Self.headerSize
            return (0..<channelCount).map { channel in
                (0..<frames).map { frame in
                    let index = interleaved ? frame * channelCount + channel : channel * frames + frame
                    return raw.loadUnaligned(fromByteOffset: base + index * 4, as: Float.self)
                }
            }
        }
        self.sampleRate = sampleRate
    }

    // MARK: - Conversion

    /// The audio as a non-interleaved Float32 `AVAudioPCMBuffer`.
    public func pcmBuffer() throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channelCount)),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let destination = buffer.floatChannelData
        else {
            throw AudioHelpers.AudioError.bufferCreationFailed
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        for (index, samples) in channels.enumerated() {
            samples.withUnsafeBufferPointer { source in
                destination[index].update(from: source.baseAddress!, count: frameCount)
            }
        }
        return buffer
    }

    /// The audio as a 32-bit float WAV file, built in memory.
    public func wavData() -> Data {
        let bytesPerSample = 4
        let blockAlign = channelCount * bytesPerSample
        let dataSize = frameCount * blockAlign
        var data = Data(capacity: 58 + dataSize)

        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(50 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        // fmt chunk: IEEE float (format 3), which needs the 18-byte form and a fact chunk.
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(18))
        append(UInt16(3))
        append(UInt16(channelCount))
        append(UInt32(sampleRate.rounded()))
        append(UInt32((sampleRate.rounded()) * Double(blockAlign)))
        append(UInt16(blockAlign))
        append(UInt16(bytesPerSample * 8))
        append(UInt16(0))
        data.append(contentsOf: Array("fact".utf8))
        append(UInt32(4))
        append(UInt32(frameCount))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize))
        for frame in 0..<frameCount {
            for channel in channels {
                append(channel[frame].bitPattern)
            }
        }
        return data
    }
}
