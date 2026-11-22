//
//  AudioHelpers.swift
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

public enum AudioHelpers {

    public enum AudioError: Error, Sendable, CustomStringConvertible {
        case invalidData(String)
        case unsupportedDataType(UInt32)
        case bufferCreationFailed
        case fileWriteFailed

        public var description: String {
            switch self {
            case .invalidData(let detail):
                return "Audio tensor data invalid: \(detail)"
            case .unsupportedDataType(let type):
                return "Unsupported tensor data type: 0x\(String(type, radix: 16)). Expected CCV_32F (0x4000)."
            case .bufferCreationFailed:
                return "Failed to create AVAudioPCMBuffer"
            case .fileWriteFailed:
                return "Failed to write audio buffer to WAV file"
            }
        }
    }

    /// Convert a CCV tensor (raw Float32 waveform) to an AVAudioPCMBuffer.
    ///
    /// - Parameters:
    ///   - data: Raw CCV tensor bytes (68-byte header + Float32 sample data)
    ///   - sampleRate: Audio sample rate in Hz; see ``ModelFamily/audioSampleRate``
    /// - Returns: An AVAudioPCMBuffer containing the decoded audio
    public static func ccvTensorToAudioBuffer(_ data: Data, sampleRate: Double = ModelFamily.defaultAudioSampleRate) throws -> AVAudioPCMBuffer {
        try GeneratedAudio(tensor: data, sampleRate: sampleRate).pcmBuffer()
    }

    /// Convert an AVAudioPCMBuffer to WAV file data.
    ///
    /// - Parameter buffer: The audio buffer to convert
    /// - Returns: WAV file data that can be written to disk
    public static func audioBufferToWAVData(_ buffer: AVAudioPCMBuffer) throws -> Data {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        do {
            let file = try AVAudioFile(
                forWriting: tempURL,
                settings: buffer.format.settings
            )
            try file.write(from: buffer)
        } catch {
            throw AudioError.fileWriteFailed
        }

        do {
            return try Data(contentsOf: tempURL)
        } catch {
            throw AudioError.fileWriteFailed
        }
    }
}
