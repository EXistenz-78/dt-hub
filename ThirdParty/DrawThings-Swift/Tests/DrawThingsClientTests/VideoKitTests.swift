import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import DrawThingsClient
@testable import DrawThingsVideoKit

extension Trait where Self == ConditionTrait {
    /// For tests that encode video. AVAssetWriter crashes the test process intermittently
    /// (SIGSEGV) on GitHub's macOS 15 runner VMs, including for a plain video with no audio;
    /// it has not crashed on real hardware. Run these tests locally.
    static var writesVideo: Self {
        .disabled(
            if: ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
            "AVAssetWriter crashes intermittently on GitHub's macOS runner VMs"
        )
    }
}

/// Solid-color frames and generated results for the video tests.
enum VideoFixtures {
    static func frame(width: Int = 64, height: Int = 64, gray: CGFloat) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(gray: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func frames(_ count: Int) -> [CGImage] {
        (0..<count).map { frame(gray: CGFloat($0) / CGFloat(max(1, count - 1))) }
    }

    /// One second of a 440 Hz stereo tone.
    static let tone = GeneratedAudio(
        channels: Array(repeating: (0..<24_000).map { sin(Float($0) * 2 * .pi * 440 / 24_000) * 0.3 }, count: 2),
        sampleRate: 24_000
    )

    static func result(frames: Int, isVideo: Bool = true, frameRate: Int = 16, audio: [GeneratedAudio] = []) -> GenerationResult {
        let request = GenerationRequest(
            prompt: "a waving flag",
            configuration: DrawThingsConfiguration(width: 64, height: 64, model: "wan_v2.1_1.3b_480p_f16.ckpt", seed: 42, numFrames: Int32(frames))
        )
        return GenerationResult(
            request: request,
            images: self.frames(frames),
            audio: audio,
            media: MediaProfile(family: .wan21, isVideo: isVideo, frameRate: isVideo ? frameRate : nil, audioSampleRate: nil),
            startedAt: Date(),
            completedAt: Date()
        )
    }

    static func temporaryURL(_ ext: String = "mp4") -> URL {
        FileManager.default.temporaryDirectory.appending(path: "videokit-\(UUID().uuidString).\(ext)")
    }

    struct VideoInfo {
        var duration: Double
        var size: CGSize
        var frameCount: Int
        var hasAudio: Bool
    }

    static func inspect(_ url: URL) async throws -> VideoInfo {
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        reader.startReading()
        var frameCount = 0
        // Passthrough reading also returns marker buffers that hold no frames.
        while let buffer = output.copyNextSampleBuffer() { frameCount += CMSampleBufferGetNumSamples(buffer) }
        return VideoInfo(
            duration: try await asset.load(.duration).seconds,
            size: try await track.load(.naturalSize),
            frameCount: frameCount,
            hasAudio: !(try await asset.loadTracks(withMediaType: .audio).isEmpty)
        )
    }
}

@Suite("VideoAssembler")
struct VideoAssemblerTests {
    @Test(.writesVideo) func writesFramesAtTheSourceFrameRate() async throws {
        let url = VideoFixtures.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let assembler = VideoAssembler()
        let progress = ProgressRecorder()

        let output = try await assembler.assemble(
            frames: VideoFrameCollection(cgImages: VideoFixtures.frames(16)),
            configuration: VideoConfiguration(outputURL: url, sourceFrameRate: 16),
            progress: { progress.record($0) }
        )

        let info = try await VideoFixtures.inspect(output)
        #expect(info.frameCount == 16)
        #expect(abs(info.duration - 1.0) < 0.1)
        #expect(info.size == CGSize(width: 64, height: 64))
        #expect(!info.hasAudio)
        #expect(progress.values.last == 1)
    }

    @Test(.writesVideo) func muxesAudioTrimmedToTheVideo() async throws {
        let url = VideoFixtures.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let output = try await VideoAssembler().assemble(
            frames: VideoFrameCollection(cgImages: VideoFixtures.frames(8)),  // 0.5 s at 16 fps
            configuration: VideoConfiguration(outputURL: url, sourceFrameRate: 16, audioData: VideoFixtures.tone.wavData())
        )
        let info = try await VideoFixtures.inspect(output)
        #expect(info.hasAudio)
        #expect(abs(info.duration - 0.5) < 0.1)
    }

    @Test(.writesVideo) func coreImageInterpolationAndUpscaling() async throws {
        let url = VideoFixtures.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let assembler = VideoAssembler(preferredInterpolationMethod: .coreImageDissolve, preferredSuperResolutionMethod: .coreImageLanczos)
        let output = try await assembler.assemble(
            frames: VideoFrameCollection(cgImages: VideoFixtures.frames(5)),
            configuration: VideoConfiguration(
                outputURL: url, sourceFrameRate: 16, frameRate: 32,
                interpolation: .enabled(factor: 2), superResolution: .enabled(factor: 2)
            )
        )
        let info = try await VideoFixtures.inspect(output)
        #expect(info.frameCount == 9)  // 5 frames + 4 in between
        #expect(info.size == CGSize(width: 128, height: 128))
    }

    @Test func rejectsMismatchedOrMissingFrames() async throws {
        let url = VideoFixtures.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let assembler = VideoAssembler()
        await #expect(throws: VideoAssemblerError.self) {
            try await assembler.assemble(frames: VideoFrameCollection(), configuration: VideoConfiguration(outputURL: url))
        }
        let mixed = VideoFrameCollection(cgImages: [VideoFixtures.frame(gray: 0), VideoFixtures.frame(width: 32, height: 32, gray: 1)])
        await #expect(throws: VideoAssemblerError.self) {
            try await assembler.assemble(frames: mixed, configuration: VideoConfiguration(outputURL: url))
        }
    }

    @Test func coreImageInterpolationBlendsBetweenFrames() async throws {
        let frames = [VideoFixtures.frame(gray: 0), VideoFixtures.frame(gray: 1)]
        let result = try await FrameInterpolator(preferredMethod: .coreImageDissolve).interpolate(frames: frames, factor: 4, passMode: .multiPass)
        #expect(result.count == 5)
        let middle = try #require(result[2].dataProvider?.data as Data?)
        // Core Image blends in linear light, so halfway is lighter than 128 in sRGB.
        #expect((20...235).contains(Int(middle[0])))
    }
}

final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Double] = []
    func record(_ value: Double) { lock.withLock { recorded.append(value) } }
    var values: [Double] { lock.withLock { recorded } }
}

@Suite("VideoFrameCollection")
struct VideoFrameCollectionTests {
    @Test func savesAndLoadsFramesAudioAndMetadata() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "frames-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        var collection = VideoFrameCollection(cgImages: VideoFixtures.frames(3))
        collection.metadata = VideoFrameMetadata(sourceJobId: UUID(), prompt: "p", model: "m", seed: 3_000_000_000, custom: ["k": "v"])
        collection.audioData = [VideoFixtures.tone.wavData()]
        try await collection.save(to: directory)

        #expect(VideoFrameCollection.exists(at: directory))
        let loaded = try await VideoFrameCollection.load(from: directory)
        #expect(loaded.count == 3)
        #expect(loaded.cgImage(at: 2)?.width == 64)
        #expect(loaded.metadata.seed == 3_000_000_000)
        #expect(loaded.metadata.sourceJobId == collection.metadata.sourceJobId)
        #expect(loaded.metadata.custom == ["k": "v"])
        #expect(loaded.audioData == collection.audioData)
    }

    @Test func removesFramesByIndex() {
        var collection = VideoFrameCollection(cgImages: VideoFixtures.frames(5))
        let ids = collection.allCGImages().map { ObjectIdentifier($0) }
        collection.remove(at: [0, 2, 9])
        #expect(collection.allCGImages().map { ObjectIdentifier($0) } == [ids[1], ids[3], ids[4]])
    }
}

@Suite("VideoProcessor")
@MainActor
struct VideoProcessorTests {
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(20)
        while !condition() {
            guard ContinuousClock.now < deadline else { Issue.record("timed out waiting"); return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func collectsOnlyVideoResults() {
        let processor = VideoProcessor(configuration: VideoProcessorConfiguration(defaultVideoConfiguration: VideoConfiguration(outputURL: VideoFixtures.temporaryURL())))
        processor.ingest(VideoFixtures.result(frames: 1, isVideo: false))
        #expect(processor.collectedFrames.isEmpty)

        let video = VideoFixtures.result(frames: 6, audio: [VideoFixtures.tone])
        processor.ingest(video)
        #expect(processor.collectedFrames.count == 6)
        #expect(processor.collectedFrames.audioData?.count == 1)
        #expect(processor.collectedFrames.metadata.sourceJobId == video.id)
        #expect(processor.collectedFrames.metadata.seed == 42)

        // A new job replaces the previous job's frames.
        processor.ingest(VideoFixtures.result(frames: 4))
        #expect(processor.collectedFrames.count == 4)
        #expect(processor.collectedFrames.audioData == nil)
    }

    @Test(.writesVideo) func autoAssemblesEveryResultInOrderAtTheModelFrameRate() async throws {
        let urls = [UUID: URL]()
        let outputs = OutputURLs(urls)
        let processor = VideoProcessor(configuration: VideoProcessorConfiguration(
            autoAssemble: true,
            defaultVideoConfiguration: VideoConfiguration(outputURL: VideoFixtures.temporaryURL()),
            configurationProvider: { id in VideoConfiguration(outputURL: outputs.url(for: id)) }
        ))
        let events = processor.events
        let (results, continuation) = AsyncStream.makeStream(of: GenerationResult.self)
        processor.connect(to: results)

        // The second result arrives while the first is still being assembled; both get a video.
        let first = VideoFixtures.result(frames: 24, frameRate: 24, audio: [VideoFixtures.tone])
        let second = VideoFixtures.result(frames: 16, frameRate: 16)
        continuation.yield(first)
        continuation.yield(second)

        var completed: [(UUID, URL)] = []
        for await event in events {
            if case .assemblyCompleted(let id, let url) = event { completed.append((id, url)) }
            if completed.count == 2 { break }
        }
        defer { for (_, url) in completed { try? FileManager.default.removeItem(at: url) } }

        #expect(completed.map(\.0) == [first.id, second.id])
        let firstInfo = try await VideoFixtures.inspect(completed[0].1)
        let secondInfo = try await VideoFixtures.inspect(completed[1].1)
        #expect(abs(firstInfo.duration - 1.0) < 0.1)  // 24 frames at 24 fps
        #expect(firstInfo.hasAudio)
        #expect(abs(secondInfo.duration - 1.0) < 0.1)  // 16 frames at 16 fps
        #expect(!secondInfo.hasAudio)
        try await waitUntil { !processor.isAssembling }
        #expect(processor.collectedFrames.isEmpty)  // cleared after assembly
        #expect(processor.lastOutputURL == completed[1].1)
        processor.disconnect()
    }

    @Test func failedAssemblyIsReported() async throws {
        let processor = VideoProcessor(configuration: VideoProcessorConfiguration(defaultVideoConfiguration: VideoConfiguration(outputURL: VideoFixtures.temporaryURL())))
        await #expect(throws: VideoAssemblerError.self) { try await processor.assembleCollectedFrames() }
        #expect(processor.lastError is VideoAssemblerError)
        #expect(!processor.isAssembling)
    }
}

/// Hands out a file URL per job.
final class OutputURLs: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [UUID: URL]
    init(_ urls: [UUID: URL]) { self.urls = urls }
    func url(for id: UUID) -> URL {
        lock.withLock {
            if let url = urls[id] { return url }
            let url = VideoFixtures.temporaryURL()
            urls[id] = url
            return url
        }
    }
}
