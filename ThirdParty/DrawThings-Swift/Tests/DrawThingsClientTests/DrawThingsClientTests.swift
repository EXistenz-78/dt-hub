import CoreGraphics
import Foundation
import Testing
import FlatBuffers
@testable import DrawThingsClient

@Suite("Client")
struct DrawThingsClientTests {

    @Test func cGImageTensorEncoderMatchesPlatformImageWrapper() throws {
        let context = try #require(CGContext(
            data: nil,
            width: 3,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 0.25, green: 0.5, blue: 0.75, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
        let cgImage = try #require(context.makeImage())
        let platformImage = PlatformImage.fromCGImage(cgImage)

        let cgRGBA = try ImageHelpers.imageToDTTensor(cgImage, forceRGB: false)
        let platformRGBA = try ImageHelpers.imageToDTTensor(platformImage, forceRGB: false)
        #expect(cgRGBA == platformRGBA)
        let cgRGB = try ImageHelpers.imageToDTTensor(cgImage, forceRGB: true)
        let platformRGB = try ImageHelpers.imageToDTTensor(platformImage, forceRGB: true)
        #expect(cgRGB == platformRGB)
    }

    /// The seed mode must survive `toFlatBufferData()` unchanged — regression for a
    /// bug that collapsed scalealike(2) and nvidiagpucompatible(3) to
    /// torchcpucompatible, which changes the initial noise and breaks reproduction.
    @Test func seedModeSurvivesEncoding() throws {
        for expected in [SeedMode.legacy, .torchcpucompatible, .scalealike, .nvidiagpucompatible] {
            let mode = expected
            let config = DrawThingsConfiguration(
                width: 512, height: 512, steps: 20,
                model: "sd_xl_base_1.0.safetensors", guidanceScale: 7.0,
                seedMode: mode
            )
            let data = try config.toFlatBufferData()
            let buffer = ByteBuffer(data: data)
            let rootOffset = Int32(buffer.read(def: UInt32.self, position: 0))
            let root = GenerationConfiguration(buffer, o: rootOffset)
            #expect(root.seedMode == expected, "seedMode \(mode) should encode as \(expected)")
        }
    }

    /// Regression: FlatBuffers omits any scalar equal to its schema default, and
    /// the Draw Things schema defaults these to true / non-zero. Without
    /// `serializeDefaults: true` the encoder silently dropped them, the server
    /// read back its own default, and generation diverged from the app for an
    /// identical config + seed.
    @Test func schemaDefaultValuedFieldsSurviveEncoding() throws {
        let config = DrawThingsConfiguration(
            width: 1024, height: 1024, steps: 8,
            model: "z_image_turbo_1.0_q8p.ckpt", guidanceScale: 1.0,
            shift: 3.0,
            imageGuidanceScale: 0.0,
            clipWeight: 0.0,
            guidanceEmbed: 0.0,
            speedUpWithGuidanceEmbed: false,
            preserveOriginalAfterInpaint: false,
            stochasticSamplingGamma: 0.0,
            negativePromptForImagePrior: false,
            resolutionDependentShift: false,
            t5TextEncoder: false,
            teaCacheEnd: 0,
            causalInference: 0
        )
        let data = try config.toFlatBufferData()
        let buffer = ByteBuffer(data: data)
        let rootOffset = Int32(buffer.read(def: UInt32.self, position: 0))
        let root = GenerationConfiguration(buffer, o: rootOffset)

        #expect(!(root.resolutionDependentShift))
        #expect(!(root.t5TextEncoder))
        #expect(!(root.speedUpWithGuidanceEmbed))
        #expect(!(root.preserveOriginalAfterInpaint))
        #expect(!(root.negativePromptForImagePrior))
        #expect(root.imageGuidanceScale == 0.0)
        #expect(root.clipWeight == 0.0)
        #expect(root.guidanceEmbed == 0.0)
        #expect(root.stochasticSamplingGamma == 0.0)
        #expect(root.teaCacheEnd == 0)
        #expect(root.causalInference == 0)
        #expect(root.shift == 3.0)
    }

    /// The app sends 0 for unset SDXL micro-conditioning sizes; we must not
    /// substitute the start size, or our request differs from the UI's.
    @Test func unsetConditioningSizesArePassedThroughAsZero() throws {
        let config = DrawThingsConfiguration(
            width: 1024, height: 1024, steps: 8,
            model: "z_image_turbo_1.0_q8p.ckpt", guidanceScale: 1.0
        )
        let data = try config.toFlatBufferData()
        let buffer = ByteBuffer(data: data)
        let rootOffset = Int32(buffer.read(def: UInt32.self, position: 0))
        let root = GenerationConfiguration(buffer, o: rootOffset)

        #expect(root.originalImageWidth == 0)
        #expect(root.originalImageHeight == 0)
        #expect(root.targetImageWidth == 0)
        #expect(root.targetImageHeight == 0)
        #expect(root.negativeOriginalImageWidth == 0)
        #expect(root.negativeOriginalImageHeight == 0)
    }

    @Test func configurationCreation() throws {
        let config = DrawThingsConfiguration(
            width: 512,
            height: 512,
            steps: 20,
            model: "sd_xl_base_1.0.safetensors",
            guidanceScale: 7.0
        )
        
        #expect(config.width == 512)
        #expect(config.height == 512)
        #expect(config.steps == 20)
        #expect(config.guidanceScale == 7.0)
    }
    
    @Test func samplerTypes() {
        #expect(SamplerType.ddim.rawValue == 2)
        #expect(SamplerType.eulera.rawValue == 1)
        #expect(SamplerType.dpmpp2mkarras.rawValue == 0)
    }
    
    @Test func generationStageDescriptions() {
        #expect(GenerationStage.textEncoding.description == "Encoding text prompt...")
        #expect(GenerationStage.sampling(step: 5).description == "Generating image (step 5)...")
        #expect(GenerationStage.imageDecoding.description == "Decoding generated image...")
    }

    @Test func modelFamilyDetection() {
        // SD 1.x/2.x/SVD must be distinguished from SDXL (different 4-channel coefficients).
        #expect(ModelFamily.detect(from: "v1") == .sd1)
        #expect(ModelFamily.detect(from: "v2") == .sd1)
        #expect(ModelFamily.detect(from: "svd_xt_1.1.safetensors") == .sd1)
        #expect(ModelFamily.detect(from: "sd_xl_base_1.0.safetensors") == .sdxl)
        #expect(ModelFamily.detect(from: "sdxlBase") == .sdxl)
        #expect(ModelFamily.detect(from: "pixart") == .sdxl)

        // HiDream-O1 (patch decode) must not be confused with HiDream-I1 (Flux coefficients).
        #expect(ModelFamily.detect(from: "hidreamo1") == .hiDreamO1)
        #expect(ModelFamily.detect(from: "hidream_o1") == .hiDreamO1)
        #expect(ModelFamily.detect(from: "hidreami1") == .flux)

        // New models reusing existing coefficient families.
        #expect(ModelFamily.detect(from: "cosmos2_5_2b") == .qwen)
        #expect(ModelFamily.detect(from: "ernieImage") == .flux2)
        #expect(ModelFamily.detect(from: "seedvr2_3b") == .flux)

        // Newly recognized older families.
        #expect(ModelFamily.detect(from: "kandinsky21") == .kandinsky)
        #expect(ModelFamily.detect(from: "wurstchenStageC") == .wurstchen)

        // Regression checks on existing routing.
        #expect(ModelFamily.detect(from: "qwenImage") == .qwen)
        #expect(ModelFamily.detect(from: "flux1") == .flux)
        #expect(ModelFamily.detect(from: "wan22_5b") == .wan22)
        #expect(ModelFamily.detect(from: "totally-unknown-model") == .unknown)

        // MiniMax H3 and LongCat-Video Avatar (version strings and filenames).
        #expect(ModelFamily.detect(from: "minimaxH3") == .minimaxH3)
        #expect(ModelFamily.detect(from: "minimax_h3") == .minimaxH3)
        #expect(ModelFamily.detect(from: "minimax_h3_q8p.ckpt") == .minimaxH3)
        #expect(ModelFamily.detect(from: "longcatVideoAvatar1_5") == .longcatVideoAvatar)
        #expect(ModelFamily.detect(from: "longcat_video_avatar_v1.5") == .longcatVideoAvatar)
        #expect(ModelFamily.detect(from: "longcat_video_avatar_1.5_q8p.ckpt") == .longcatVideoAvatar)

        // Qwen Image 2.1 has its own 64-channel family; other Qwen Image releases stay on .qwen.
        #expect(ModelFamily.detect(from: "qwenImage2_1") == .qwen21)
        #expect(ModelFamily.detect(from: "qwen_image_2.1") == .qwen21)
        #expect(ModelFamily.detect(from: "qwen_image_2.1_q8p.ckpt") == .qwen21)
        #expect(ModelFamily.detect(from: "qwen_image_2512_q8p.ckpt") == .qwen)
        #expect(ModelFamily.detect(from: "qwen_image_edit_2511_q8p.ckpt") == .qwen)
    }

    @Test func modelFamilyChannels() {
        #expect(ModelFamily.sd1.latentChannels == 4)
        #expect(ModelFamily.kandinsky.latentChannels == 4)
        #expect(ModelFamily.wurstchen.latentChannels == 4)
        #expect(ModelFamily.flux2.latentChannels == 32)
        #expect(ModelFamily.wan22.latentChannels == 48)
        #expect(ModelFamily.hiDreamO1.latentChannels == 3 * 32 * 32)
        #expect(ModelFamily.minimaxH3.latentChannels == 24)
        #expect(ModelFamily.longcatVideoAvatar.latentChannels == 16)
        #expect(ModelFamily.qwen21.latentChannels == 64)
    }

    /// Build an uncompressed NHWC float16 DTTensor with the given per-pixel channel values.
    private func makeDTTensor(width: Int, height: Int, pixel: [Float]) -> Data {
        var header = [UInt32](repeating: 0, count: 17)
        header[2] = 0x02  // NHWC
        header[5] = 1
        header[6] = UInt32(height)
        header[7] = UInt32(width)
        header[8] = UInt32(pixel.count)
        var data = header.withUnsafeBytes { Data($0) }
        for _ in 0..<(width * height) {
            for value in pixel {
                var bits = Float16(value).bitPattern
                data.append(Data(bytes: &bits, count: 2))
            }
        }
        return data
    }

    private func firstPixelRGBA(_ image: PlatformImage) throws -> [UInt8] {
        let bitmap = try RGBA8Bitmap(try #require(image.cgImageRepresentation))
        return Array(bitmap.pixels.prefix(4))
    }

    /// Qwen Image 2.1 final images are 4-channel ARGB (alpha in [0, 1], RGB in [-1, 1]);
    /// they must not be run through the 4-channel SDXL latent matrix (which inverts colours).
    @Test func qwen21FinalImageDecodesAsARGB() throws {
        // Opaque pure red: A = 1, R = 1, G = -1, B = -1.
        let tensor = makeDTTensor(width: 2, height: 2, pixel: [1, 1, -1, -1])
        let image = try ImageHelpers.dtTensorToImage(tensor, modelFamily: .qwen21)
        #expect(try firstPixelRGBA(image) == [255, 0, 0, 255])
    }

    @Test func qwen21PreviewLatentIsSupported() throws {
        let tensor = makeDTTensor(width: 2, height: 2, pixel: [Float](repeating: 0, count: 64))
        #expect(throws: Never.self) { try ImageHelpers.dtTensorToImage(tensor, modelFamily: .qwen21) }
    }

    @Test func modelFamilyNativeFrameRate() {
        #expect(ModelFamily.minimaxH3.nativeFrameRate == 24)
        #expect(ModelFamily.longcatVideoAvatar.nativeFrameRate == 25)
        #expect(ModelFamily.flux.nativeFrameRate == nil)
    }

    @Test func miniMaxH3AudioHeight() {
        // Single frame: 1 video frame -> 2 audio rows of 32 channels = 64 values;
        // row size = 1 * 8 * 24 = 192, so 1 row holds it and 192 % 32 == 0.
        #expect(ImageHelpers.minimaxH3AudioHeight(videoLatentFrames: 1, latentWidth: 8) == 1)
        // Frame counts upstream would reject yield 0 (no stripping) instead of trapping.
        #expect(ImageHelpers.minimaxH3AudioHeight(videoLatentFrames: 3, latentWidth: 8) == 0)
        #expect(ImageHelpers.minimaxH3AudioHeight(videoLatentFrames: 7, latentWidth: 0) == 0)
        // 7 latent frames -> 22 real frames -> 2 * round(22/24*40) = 74 rows * 32 = 2368 values;
        // row size = 7 * 8 * 24 = 1344 -> ceil = 2, and 2688 % 32 == 0.
        #expect(ImageHelpers.minimaxH3AudioHeight(videoLatentFrames: 7, latentWidth: 8) == 2)
    }
}
