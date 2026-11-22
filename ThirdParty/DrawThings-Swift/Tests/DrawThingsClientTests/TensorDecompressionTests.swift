import CoreGraphics
import Foundation
import Testing
import Compression
import CFpzip
@testable import DrawThingsClient

/// Round-trips compressed CCV tensors through `TensorDecompression`, so the bundled
/// fpzip codec is exercised with the package's compiler settings.
@Suite("Tensor decompression")
struct TensorDecompressionTests {

    private let ccv32F: UInt32 = 0x04000
    private let ccv16F: UInt32 = 0x20000
    private let identifierZip: UInt32 = 0x217
    private let identifierFpzip: UInt32 = 0xf7217

    /// Deterministic, non-trivial float samples (smooth ramp plus a sine component).
    private func samples(count: Int) -> [Float] {
        // Typed steps: the single-expression form times out the type checker on some toolchains.
        (0..<count).map { i -> Float in
            let x = Float(i)
            let ramp: Float = x / Float(count) * 2 - 1
            let wave: Float = 0.1 * sin(x * 0.37)
            return ramp + wave
        }
    }

    /// Builds a 68-byte CCV tensor header followed by `payload`.
    private func tensor(identifier: UInt32, datatype: UInt32, dims: [Int32], payload: Data) -> Data {
        var header = [UInt32](repeating: 0, count: 17)
        header[0] = identifier
        header[1] = 0x1   // CPU memory
        header[2] = 0x02  // NHWC
        header[3] = datatype
        for (i, d) in dims.enumerated() { header[5 + i] = UInt32(bitPattern: d) }
        var data = header.withUnsafeBufferPointer { Data(buffer: $0) }
        data.append(payload)
        return data
    }

    private func fpzipCompress(_ values: [Float]) throws -> Data {
        var buffer = Data(count: values.count * MemoryLayout<Float>.size + 1024)
        let written = buffer.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) -> Int in
            guard let fpz = fpzip_write_to_buffer(out.baseAddress, out.count) else { return 0 }
            defer { fpzip_write_close(fpz) }
            fpz.pointee.type = FPZIP_TYPE_FLOAT
            fpz.pointee.prec = 0  // full precision (lossless)
            fpz.pointee.nx = Int32(values.count)
            fpz.pointee.ny = 1
            fpz.pointee.nz = 1
            fpz.pointee.nf = 1
            guard fpzip_write_header(fpz) != 0 else { return 0 }
            return values.withUnsafeBytes { fpzip_write(fpz, $0.baseAddress) }
        }
        #expect(written > 0, "fpzip_write failed")
        buffer.count = written
        return buffer
    }

    private func payloadFloats(_ tensor: Data) -> [Float] {
        tensor.dropFirst(68).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    private func payloadHalfBits(_ tensor: Data) -> [UInt16] {
        tensor.dropFirst(68).withUnsafeBytes { Array($0.bindMemory(to: UInt16.self)) }
    }

    @Test func uncompressedTensorIsReturnedUnchanged() throws {
        let values = samples(count: 64)
        let raw = values.withUnsafeBufferPointer { Data(buffer: $0) }
        let input = tensor(identifier: 0, datatype: ccv32F, dims: [1, 8, 8, 1], payload: raw)
        #expect(try TensorDecompression.decompressIfNeeded(input) == input)
    }

    @Test func fpzipFloat32RoundTripIsLossless() throws {
        let values = samples(count: 32 * 24 * 3)
        let input = tensor(
            identifier: identifierFpzip, datatype: ccv32F, dims: [1, 32, 24, 3],
            payload: try fpzipCompress(values)
        )

        let output = try TensorDecompression.decompressIfNeeded(input)

        #expect(output.prefix(4) == Data(count: 4), "identifier must be reset to uncompressed")
        #expect(output.subdata(in: 4..<68) == input.subdata(in: 4..<68), "tensor params must be preserved")
        #expect(payloadFloats(output) == values)
    }

    @Test func fpzipFloat16TensorIsConvertedToHalfPrecision() throws {
        // Float16 tensors are stored by fpzip as Float32 and narrowed on decode.
        let values = samples(count: 16 * 16 * 4)
        let input = tensor(
            identifier: identifierFpzip, datatype: ccv16F, dims: [1, 16, 16, 4],
            payload: try fpzipCompress(values)
        )

        let output = try TensorDecompression.decompressIfNeeded(input)

        #expect(output.count == 68 + values.count * 2)
        #expect(payloadHalfBits(output) == values.map { Float16($0).bitPattern })
    }

    @Test func deflateRoundTrip() throws {
        let values = samples(count: 4096)
        let raw = values.withUnsafeBufferPointer { Data(buffer: $0) }
        var compressed = Data(count: raw.count + 1024)
        let size = compressed.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) in
            raw.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
                compression_encode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, dst.count,
                    src.bindMemory(to: UInt8.self).baseAddress!, src.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        #expect(size > 0)
        compressed.count = size

        let input = tensor(identifier: identifierZip, datatype: ccv32F, dims: [1, 64, 64, 1], payload: compressed)
        let output = try TensorDecompression.decompressIfNeeded(input)

        #expect(payloadFloats(output) == values)
    }

    @Test func truncatedFpzipPayloadThrows() throws {
        let values = samples(count: 64 * 64)
        let compressed = try fpzipCompress(values)
        // Keep the fpzip header but cut the stream at several points.
        for keep in [compressed.count / 2, compressed.count - 1, 24, 8] {
            let input = tensor(identifier: identifierFpzip, datatype: ccv32F, dims: [1, 64, 64, 1],
                               payload: compressed.prefix(keep))
            #expect(throws: (any Error).self, "kept \(keep) of \(compressed.count) bytes") { try TensorDecompression.decompressIfNeeded(input) }
        }
    }

    @Test func fpzipHeaderMustMatchTensorHeader() throws {
        let compressed = try fpzipCompress(samples(count: 100))
        // Tensor header claims 200 elements; the stream has 100.
        let input = tensor(identifier: identifierFpzip, datatype: ccv32F, dims: [1, 200], payload: compressed)
        #expect(throws: (any Error).self) { try TensorDecompression.decompressIfNeeded(input) }
    }
}
