//
//  TensorDecompression.swift
//  DrawThingsClient
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import Accelerate
import Compression
import Foundation
import CFpzip

/// Handles decompression of CCV tensors that may be compressed with zip (deflate) or fpzip codecs.
///
/// The CCV tensor binary format is:
/// - Bytes 0-3: UInt32 identifier (0 = uncompressed, 0x217 = deflate, 0xf7217 = fpzip)
/// - Bytes 4-67: ccv_nnc_tensor_param_t (type, format, datatype, reserved, dim[12])
/// - Bytes 68+: tensor data (raw or compressed)
///
/// Tensor data comes from the network, so every size taken from a header is validated before
/// memory is allocated or read.
enum TensorDecompression {

    enum DecompressionError: Error, CustomStringConvertible {
        case unsupportedCompression(UInt32)
        case deflateFailed
        case fpzipFailed(String)
        case dataTooSmall
        case invalidDimensions

        var description: String {
            switch self {
            case .unsupportedCompression(let id):
                return "Unsupported tensor compression identifier: 0x\(String(id, radix: 16))"
            case .deflateFailed:
                return "Failed to decompress deflate-compressed tensor data"
            case .fpzipFailed(let reason):
                return "Failed to decompress fpzip-compressed tensor data: \(reason)"
            case .dataTooSmall:
                return "Tensor data is too small to contain a valid header"
            case .invalidDimensions:
                return "Tensor header has invalid or oversized dimensions"
            }
        }
    }

    // Compression identifiers from s4nnc Store.Codec
    private static let identifierUncompressed: UInt32 = 0
    private static let identifierZip: UInt32 = 0x217
    private static let identifierFpzip: UInt32 = 0xf7217

    // CCV data type constants
    private static let ccv16F: UInt32 = 0x20000
    private static let ccv32F: UInt32 = 0x04000
    private static let ccv64F: UInt32 = 0x10000

    static let headerSize = 68

    /// Largest element count accepted from a tensor header (4 GiB of Float32).
    static let maxElements = 1 << 30

    /// Decompress tensor data if compressed, returning uncompressed tensor data.
    ///
    /// If the tensor is already uncompressed (identifier == 0), returns the data unchanged.
    /// Supports deflate (identifier 0x217) and fpzip (identifier 0xf7217) compression.
    ///
    /// - Parameter data: Raw tensor bytes (68-byte header + possibly compressed payload)
    /// - Returns: Tensor data with uncompressed payload
    static func decompressIfNeeded(_ data: Data) throws -> Data {
        guard data.count >= headerSize else {
            throw DecompressionError.dataTooSmall
        }

        let (identifier, datatype, dims) = data.withUnsafeBytes { raw in
            (
                raw.loadUnaligned(as: UInt32.self),
                raw.loadUnaligned(fromByteOffset: 12, as: UInt32.self),
                (0..<12).map { raw.loadUnaligned(fromByteOffset: 16 + $0 * 4, as: Int32.self) }
            )
        }

        if identifier == identifierUncompressed {
            return data
        }

        let payload = data.subdata(in: (data.startIndex + headerSize)..<data.endIndex)

        let decompressedPayload: Data
        switch identifier {
        case identifierZip:
            decompressedPayload = try decompressDeflate(payload)
        case identifierFpzip:
            decompressedPayload = try decompressFpzip(payload, datatype: datatype, elementCount: try elementCount(dims))
        default:
            throw DecompressionError.unsupportedCompression(identifier)
        }

        // Reconstruct an uncompressed tensor: zero identifier + original params + payload.
        var result = Data(count: 4)
        result.append(data.subdata(in: (data.startIndex + 4)..<(data.startIndex + headerSize)))
        result.append(decompressedPayload)
        return result
    }

    /// The product of the positive dimensions, rejecting negative sizes, overflow and tensors
    /// larger than ``maxElements``.
    static func elementCount(_ dims: [Int32]) throws -> Int {
        var count = 1
        for dim in dims {
            if dim < 0 { throw DecompressionError.invalidDimensions }
            if dim == 0 { continue }
            let (product, overflow) = count.multipliedReportingOverflow(by: Int(dim))
            guard !overflow, product <= maxElements else { throw DecompressionError.invalidDimensions }
            count = product
        }
        return count
    }

    // MARK: - Deflate Decompression

    /// Decompress raw DEFLATE data using Apple's Compression framework.
    private static func decompressDeflate(_ data: Data) throws -> Data {
        guard !data.isEmpty else { throw DecompressionError.deflateFailed }

        // Try a single-shot decode into a generous buffer first.
        let capacity = min(data.count * 10, maxElements * 4)
        var output = Data(count: capacity)
        let size = data.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
            output.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) -> Int in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, destination.count,
                    source.bindMemory(to: UInt8.self).baseAddress!, source.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard size > 0 else { throw DecompressionError.deflateFailed }
        // A full buffer may mean the output was truncated; decode again as a stream.
        if size == capacity {
            return try decompressDeflateStreaming(data)
        }
        output.count = size
        return output
    }

    /// Streaming deflate decompression for payloads that expand more than 10×.
    private static func decompressDeflateStreaming(_ data: Data) throws -> Data {
        var result = Data()
        let bufferSize = 65_536
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }

        var status = compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard status == COMPRESSION_STATUS_OK else {
            throw DecompressionError.deflateFailed
        }
        defer { compression_stream_destroy(stream) }

        try data.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
            stream.pointee.src_ptr = source.bindMemory(to: UInt8.self).baseAddress!
            stream.pointee.src_size = source.count

            repeat {
                stream.pointee.dst_ptr = buffer
                stream.pointee.dst_size = bufferSize
                status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = bufferSize - stream.pointee.dst_size
                if produced > 0 {
                    result.append(buffer, count: produced)
                    guard result.count <= maxElements * 4 else { throw DecompressionError.deflateFailed }
                }
            } while status == COMPRESSION_STATUS_OK
        }

        guard status == COMPRESSION_STATUS_END else {
            throw DecompressionError.deflateFailed
        }
        return result
    }

    // MARK: - FPZIP Decompression

    /// Decompress fpzip-compressed tensor data.
    ///
    /// For Float16 tensors, fpzip stores Float32 data; it is narrowed back to Float16 after
    /// decompression. The fpzip stream's own header must agree with the tensor header (element
    /// count and float width) before any output memory is allocated.
    private static func decompressFpzip(_ data: Data, datatype: UInt32, elementCount: Int) throws -> Data {
        guard !data.isEmpty, elementCount > 0 else { throw DecompressionError.fpzipFailed("empty tensor") }

        let isDouble: Bool
        switch datatype {
        case ccv16F, ccv32F: isDouble = false
        case ccv64F: isDouble = true
        default: throw DecompressionError.fpzipFailed("unsupported data type 0x\(String(datatype, radix: 16))")
        }
        let elementSize = isDouble ? 8 : 4

        var decoded = Data(count: elementCount * elementSize)
        try data.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
            // Bounded reader: a truncated stream fails instead of reading past the buffer.
            guard let fpz = fpzip_read_from_buffer_size(source.baseAddress!, source.count) else {
                throw DecompressionError.fpzipFailed("could not open stream")
            }
            defer { fpzip_read_close(fpz) }

            guard fpzip_read_header(fpz) != 0 else {
                throw DecompressionError.fpzipFailed("invalid header")
            }
            let header = fpz.pointee
            guard header.type == (isDouble ? FPZIP_TYPE_DOUBLE : FPZIP_TYPE_FLOAT) else {
                throw DecompressionError.fpzipFailed("stream precision does not match the tensor data type")
            }
            var streamElements = 1
            for dim in [header.nx, header.ny, header.nz, header.nf] {
                let (product, overflow) = streamElements.multipliedReportingOverflow(by: Int(dim))
                guard dim > 0, !overflow else { throw DecompressionError.fpzipFailed("invalid stream dimensions") }
                streamElements = product
            }
            guard streamElements == elementCount else {
                throw DecompressionError.fpzipFailed("stream has \(streamElements) elements, tensor header has \(elementCount)")
            }

            try decoded.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) in
                guard fpzip_read(fpz, destination.baseAddress!) != 0 else {
                    throw DecompressionError.fpzipFailed("corrupt stream")
                }
            }
        }

        guard datatype == ccv16F else { return decoded }
        return try narrowToFloat16(decoded, count: elementCount)
    }

    /// Converts Float32 values to Float16 bit patterns with Accelerate (round to nearest even),
    /// which works on both Apple silicon and Intel.
    private static func narrowToFloat16(_ floats: Data, count: Int) throws -> Data {
        var halves = Data(count: count * 2)
        var error = kvImageNoError
        floats.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
            halves.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) in
                var sourceBuffer = vImage_Buffer(
                    data: UnsafeMutableRawPointer(mutating: source.baseAddress!),
                    height: 1, width: vImagePixelCount(count), rowBytes: count * 4)
                var destinationBuffer = vImage_Buffer(
                    data: destination.baseAddress!, height: 1, width: vImagePixelCount(count), rowBytes: count * 2)
                error = vImageConvert_PlanarFtoPlanar16F(&sourceBuffer, &destinationBuffer, vImage_Flags(kvImageNoFlags))
            }
        }
        guard error == kvImageNoError else { throw DecompressionError.fpzipFailed("Float16 conversion failed (\(error))") }
        return halves
    }
}
