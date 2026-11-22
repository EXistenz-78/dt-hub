import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import DrawThingsClient

@Suite("Generation types")
struct GenerationTypeTests {
    @Test func mapsSignpostsToStages() {
        let sampling = ImageGenerationSignpostProto.with { $0.sampling = .with { $0.step = 7 } }
        #expect(GenerationStage(sampling) == .sampling(step: 7))
        let decoded = ImageGenerationSignpostProto.with { $0.imageDecoded = .init() }
        #expect(GenerationStage(decoded) == .imageDecoding)
        #expect(GenerationStage(ImageGenerationSignpostProto()) == nil)
    }

    @Test func progressFractionOnlyDuringFirstPassSampling() {
        #expect(GenerationProgress(stage: .sampling(step: 5), step: 5, totalSteps: 20).fractionCompleted == 0.25)
        #expect(GenerationProgress(stage: .sampling(step: 30), step: 30, totalSteps: 20).fractionCompleted == 1)
        #expect(GenerationProgress(stage: .imageDecoding, totalSteps: 20).fractionCompleted == nil)
        #expect(GenerationProgress(stage: .secondPassSampling(step: 2), step: 2, totalSteps: 20).fractionCompleted == nil)
    }

    @Test func imageModelsAreNeverVideo() {
        // numFrames defaults to 14 for every configuration.
        let media = MediaProfile(configuration: DrawThingsConfiguration(model: "sd_xl_base_1.0_f16.ckpt"))
        #expect(!media.isVideo)
        #expect(media.frameRate == nil)
        #expect(media.audioSampleRate == nil)
    }

    @Test func videoModelsResolveFrameAndSampleRates() {
        let media = MediaProfile(configuration: DrawThingsConfiguration(model: "ltx_2.3_22b_distilled_f16.ckpt", numFrames: 49))
        #expect(media.family == .ltx23)
        #expect(media.isVideo)
        #expect(media.frameRate == 25)
        #expect(media.audioSampleRate == 48_000)

        let single = MediaProfile(configuration: DrawThingsConfiguration(model: "wan_v2.1_14b_t2v_q8p.ckpt", numFrames: 1))
        #expect(!single.isVideo)
    }

    /// Frame rates follow Draw Things' `ModelZoo.framesPerSecondForModel`: the spec's own rate,
    /// then its version's, then the family's.
    @Test func specFrameRatesTakePrecedence() throws {
        func spec(_ json: String) throws -> ModelSpec { try #require(ModelSpec(json: Data(json.utf8))) }

        // Some Wan 2.1 14B models run at 24 fps rather than the family's 16.
        let wan24 = try spec(#"{"file":"wan_24.ckpt","version":"wan_v2.1_14b","frames_per_second":24}"#)
        let wan = MediaProfile(configuration: DrawThingsConfiguration(model: "wan_24.ckpt", numFrames: 21), spec: wan24)
        #expect(wan.isVideo)
        #expect(wan.frameRate == 24)

        // SVD decodes with the SD 1.x family but is a 30 fps video model.
        let svd = MediaProfile(configuration: DrawThingsConfiguration(model: "svd_i2v_1.1_q8p.ckpt", numFrames: 14),
                               spec: try spec(#"{"file":"svd_i2v_1.1_q8p.ckpt","version":"svd_i2v"}"#))
        #expect(svd.family == .sd1)
        #expect(svd.isVideo)
        #expect(svd.frameRate == 30)

        // An image model stays an image model whatever its spec says.
        let image = MediaProfile(configuration: DrawThingsConfiguration(model: "flux.ckpt"),
                                 spec: try spec(#"{"file":"flux.ckpt","version":"flux1","frames_per_second":30}"#))
        #expect(!image.isVideo)
        #expect(image.frameRate == nil)

        // Without a spec: the family's rate.
        #expect(ModelFamily.hunyuanVideo.nativeFrameRate == 30)
        #expect(ModelFamily.wan22.nativeFrameRate == 24)
        #expect(ModelFamily.frameRate(forVersion: "flux1") == nil)
    }

    @Test func requestOverridesWin() {
        let request = GenerationRequest(
            prompt: "x",
            configuration: DrawThingsConfiguration(model: "custom_video_model.ckpt", numFrames: 9),
            modelFamily: .minimaxH3,
            audioSampleRate: 44_100
        )
        #expect(request.media.family == .minimaxH3)
        #expect(request.media.isVideo)
        #expect(request.media.audioSampleRate == 44_100)
    }
}

@Suite("GeneratedAudio")
struct GeneratedAudioTests {
    /// A CCV Float32 tensor: 68-byte header then samples.
    private func tensor(dims: [UInt32], format: UInt32, samples: [Float]) -> Data {
        var header = [UInt32](repeating: 0, count: 17)
        header[1] = 1
        header[2] = format
        header[3] = 0x04000
        for (i, d) in dims.enumerated() { header[5 + i] = d }
        var data = header.withUnsafeBufferPointer { Data(buffer: $0) }
        samples.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        return data
    }

    @Test func decodesPlanarStereo() throws {
        // [channels, samples] planar: L L L R R R
        let audio = try GeneratedAudio(tensor: tensor(dims: [2, 3], format: 0x01, samples: [0.1, 0.2, 0.3, -0.1, -0.2, -0.3]), sampleRate: 24_000)
        #expect(audio.channelCount == 2)
        #expect(audio.frameCount == 3)
        #expect(audio.channels[0] == [0.1, 0.2, 0.3])
        #expect(audio.channels[1] == [-0.1, -0.2, -0.3])
    }

    @Test func decodesInterleavedNHWC() throws {
        // [1, H=3, W=1, C=2] interleaved: L R L R L R
        let audio = try GeneratedAudio(tensor: tensor(dims: [1, 3, 1, 2], format: 0x02, samples: [0.1, -0.1, 0.2, -0.2, 0.3, -0.3]), sampleRate: 24_000)
        #expect(audio.channels == [[0.1, 0.2, 0.3], [-0.1, -0.2, -0.3]])
    }

    @Test func rejectsTruncatedOrOverflowingTensors() {
        #expect(throws: (any Error).self) {
            try GeneratedAudio(tensor: tensor(dims: [2, 1000], format: 0x01, samples: [0, 0]), sampleRate: 24_000)
        }
        #expect(throws: (any Error).self) {
            try GeneratedAudio(tensor: tensor(dims: [1, .max, .max, 1], format: 0x02, samples: []), sampleRate: 24_000)
        }
    }

    @Test func wavDataRoundTripsThroughAVAudioFile() throws {
        let samples: [Float] = (0..<480).map { sin(Float($0) * 0.05) * 0.5 }
        let audio = GeneratedAudio(channels: [samples, samples.map { -$0 }], sampleRate: 48_000)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try audio.wavData().write(to: url)

        let file = try AVAudioFile(forReading: url)
        #expect(file.fileFormat.sampleRate == 48_000)
        #expect(file.fileFormat.channelCount == 2)
        #expect(file.length == 480)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 480))
        try file.read(into: buffer)
        let left = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: 480)
        let right = UnsafeBufferPointer(start: buffer.floatChannelData![1], count: 480)
        #expect(Array(left) == samples)
        #expect(Array(right) == samples.map { -$0 })
    }

    @Test func pcmBufferMatchesSamples() throws {
        let audio = GeneratedAudio(channels: [[0.25, 0.5]], sampleRate: 16_000)
        let buffer = try audio.pcmBuffer()
        #expect(buffer.frameLength == 2)
        #expect(buffer.format.sampleRate == 16_000)
        #expect(buffer.floatChannelData![0][1] == 0.5)
    }
}

@Suite("Image tensors")
struct ImageTensorTests {
    @Test func rgbTensorRoundTripsToCGImage() throws {
        let width = 8, height = 4
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let source = try #require(context.makeImage())

        let tensor = try ImageHelpers.imageToDTTensor(source, forceRGB: true)
        let decoded = try ImageHelpers.dtTensorToCGImage(tensor)

        #expect(decoded.width == width)
        #expect(decoded.height == height)
        let pixels = try #require(decoded.dataProvider?.data as Data?)
        // Float16 round-trip of 0.5 can land on 127 or 128.
        #expect(pixels[0] == 255)
        #expect((127...128).contains(pixels[1]))
        #expect(pixels[2] == 0)
    }

    private func solidImage(width: Int, height: Int, gray: CGFloat, alpha: CGFloat = 1) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: gray, green: gray, blue: gray, alpha: alpha))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    private func payloadHalves(_ tensor: Data) -> [Float16] {
        tensor.dropFirst(68).withUnsafeBytes { raw in
            (0..<(raw.count / 2)).map { Float16(bitPattern: raw.loadUnaligned(fromByteOffset: $0 * 2, as: UInt16.self)) }
        }
    }

    @Test func encoderMapsBytesToMinusOneToOne() throws {
        #expect(payloadHalves(try ImageHelpers.imageToDTTensor(solidImage(width: 2, height: 2, gray: 0), forceRGB: true)).allSatisfy { $0 == -1 })
        #expect(payloadHalves(try ImageHelpers.imageToDTTensor(solidImage(width: 2, height: 2, gray: 1), forceRGB: true)).allSatisfy { $0 == 1 })
    }

    @Test func encoderHeaderAndTransparency() throws {
        let opaque = try ImageHelpers.imageToDTTensor(solidImage(width: 5, height: 3, gray: 0.5))
        let transparent = try ImageHelpers.imageToDTTensor(solidImage(width: 5, height: 3, gray: 0.5, alpha: 0.5))
        let forced = try ImageHelpers.imageToDTTensor(solidImage(width: 5, height: 3, gray: 0.5, alpha: 0.5), forceRGB: true)
        func dims(_ data: Data) -> [UInt32] { data.withUnsafeBytes { raw in (5...8).map { raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self) } } }
        #expect(dims(opaque) == [1, 3, 5, 3])
        #expect(dims(transparent) == [1, 3, 5, 4])
        #expect(dims(forced) == [1, 3, 5, 3])
        #expect(opaque.count == 68 + 5 * 3 * 3 * 2)
    }

    @Test func acceleratedDecodeMatchesScalarPath() {
        // Every Float16 value in and slightly beyond [-1, 1], plus infinities.
        var values: [UInt16] = stride(from: Float(-1.2), through: 1.2, by: 0.0007).map { Float16($0).bitPattern }
        values += [Float16.infinity.bitPattern, (-Float16.infinity).bitPattern]
        var fast = [UInt8](repeating: 0, count: values.count)
        var scalar = [UInt8](repeating: 0, count: values.count)
        values.withUnsafeBufferPointer { input in
            ImageHelpers.convert3ChannelToRGBAccelerated(float16Ptr: input.baseAddress!, uint8Ptr: &fast, count: values.count)
            ImageHelpers.convert3ChannelToRGB(float16Ptr: input.baseAddress!, uint8Ptr: &scalar, pixelCount: values.count)
        }
        // vImage rounds where the scalar path truncates: allow a difference of one level for
        // finite values. Infinities clamp to black/white instead of the scalar path's mid-gray.
        let finite = values.count - 2
        let differences = zip(fast.prefix(finite), scalar.prefix(finite)).enumerated().filter { abs(Int($0.element.0) - Int($0.element.1)) > 1 }
        #expect(differences.isEmpty, "first mismatches: \(differences.prefix(5).map { (Float(Float16(bitPattern: values[$0.offset])), $0.element.0, $0.element.1) })")
        #expect(fast[finite] == 255)
        #expect(fast[finite + 1] == 0)
    }

    @Test func malformedTensorsThrowInsteadOfCrashing() throws {
        let valid = try ImageHelpers.imageToDTTensor(solidImage(width: 4, height: 4, gray: 0.3), forceRGB: true)
        // Truncated payload.
        #expect(throws: (any Error).self) { try ImageHelpers.dtTensorToCGImage(valid.prefix(100)) }
        // Hostile dimensions: huge, zero and overflowing.
        for dims: [UInt32] in [[1, 0xFFFF_FFFF, 0xFFFF_FFFF, 3], [1, 0, 4, 3], [1, 4, 4, 0], [1, 1 << 31, 1 << 31, 64]] {
            var tensor = valid
            tensor.withUnsafeMutableBytes { raw in
                for (index, value) in dims.enumerated() { raw.storeBytes(of: value, toByteOffset: (5 + index) * 4, as: UInt32.self) }
            }
            #expect(throws: (any Error).self) { try ImageHelpers.dtTensorToCGImage(tensor) }
        }
        // Unsupported compression identifier and a corrupt fpzip payload.
        for identifier: UInt32 in [0x1234, 0xf7217] {
            var tensor = valid
            tensor.withUnsafeMutableBytes { $0.storeBytes(of: identifier, toByteOffset: 0, as: UInt32.self) }
            #expect(throws: (any Error).self) { try ImageHelpers.dtTensorToCGImage(tensor) }
        }
    }

    @Test func misalignedTensorDataDecodes() throws {
        let tensor = try ImageHelpers.imageToDTTensor(solidImage(width: 3, height: 3, gray: 0.7), forceRGB: true)
        var shifted = Data([0])
        shifted.append(tensor)
        let slice = shifted.dropFirst()  // payload now starts at an odd address
        let image = try ImageHelpers.dtTensorToCGImage(Data(slice))
        #expect(image.width == 3)
        let sliceImage = try ImageHelpers.dtTensorToCGImage(slice)
        #expect(sliceImage.height == 3)
    }
}
