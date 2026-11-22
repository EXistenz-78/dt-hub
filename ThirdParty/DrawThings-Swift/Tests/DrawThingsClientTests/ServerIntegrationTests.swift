import CryptoKit
import Foundation
import GRPCCore
import Synchronization
import Testing
@testable import DrawThingsClient

/// End-to-end tests of the client against an in-process gRPC server.
@Suite("Server integration")
struct ServerIntegrationTests {
    /// A model with a spec in the bundled models.json. (Quantized variants such as `_q8p` are
    /// built into Draw Things itself, so the snapshot only needs the live list's files.)
    static let bundledModel = "z_image_turbo_1.0_f16.ckpt"

    private func request(_ configuration: DrawThingsConfiguration = DrawThingsConfiguration(width: 64, height: 64, steps: 3, model: bundledModel)) -> GenerationRequest {
        GenerationRequest(prompt: "test", configuration: configuration)
    }

    private func label(_ event: GenerationEvent) -> String {
        switch event {
        case .progress(let progress): return "progress(\(progress.stage))"
        case .preview: return "preview"
        case .remoteDownload: return "download"
        case .image(_, let index): return "image\(index)"
        case .audio: return "audio"
        case .completed: return "completed"
        }
    }

    @Test func eventsArriveInServerOrderAndCompleteLast() async throws {
        let image = try FakeResponses.imageTensor(width: 64, height: 64)
        let audio = FakeResponses.audioTensor(samples: 3_000)
        let server = try await FakeDrawThingsServer { _, writer in
            try await writer.write(FakeResponses.textEncoded)
            for step: Int32 in 1...3 {
                try await writer.write(FakeResponses.sampling(step))
                try await writer.write(FakeResponses.preview(image))
            }
            try await writer.write(FakeResponses.imageDecoded)
            for part in FakeResponses.chunked(image: image, chunkSize: 5_000) { try await writer.write(part) }
            for part in FakeResponses.chunked(audio: audio, chunkSize: 7_000) { try await writer.write(part) }
        }
        defer { Task { await server.stop() } }
        let service = server.makeService()

        var labels: [String] = []
        var result: GenerationResult?
        for try await event in service.stream(request()) {
            labels.append(label(event))
            if case .completed(let completed) = event { result = completed }
        }

        #expect(labels == [
            "progress(Encoding text prompt...)",
            "progress(Generating image (step 1)...)", "preview",
            "progress(Generating image (step 2)...)", "preview",
            "progress(Generating image (step 3)...)", "preview",
            "progress(Decoding generated image...)",
            "image0", "audio", "completed",
        ])
        let completed = try #require(result)
        #expect(completed.images.map(\.width) == [64])
        #expect(completed.audio.first?.frameCount == 3_000)
        #expect(completed.audio.first?.channelCount == 2)
        await service.shutdown()
    }

    @Test func batchOfImagesKeepsOrder() async throws {
        let tensors = try [0.1, 0.5, 0.9].map { try FakeResponses.imageTensor(width: 64, height: 64, gray: $0) }
        let server = try await FakeDrawThingsServer { _, writer in
            for tensor in tensors {
                for part in FakeResponses.chunked(image: tensor, chunkSize: 10_000) { try await writer.write(part) }
            }
        }
        defer { Task { await server.stop() } }
        let service = server.makeService()

        let result = try await service.generate(request())
        let firstPixels = try result.images.map { try #require(($0.dataProvider?.data as Data?)?.first) }
        #expect(firstPixels.count == 3)
        #expect(firstPixels == firstPixels.sorted())  // dark, middle, light
        await service.shutdown()
    }

    @Test func messagesLargerThanFourMegabytesAreAccepted() async throws {
        // 1024x1024 RGB Float16 = 6 MiB in a single unchunked message.
        let image = try FakeResponses.imageTensor(width: 1024, height: 1024)
        let server = try await FakeDrawThingsServer { _, writer in
            try await writer.write(ImageGenerationResponse.with { $0.generatedImages = [image] })
        }
        defer { Task { await server.stop() } }
        let service = server.makeService()
        let result = try await service.generate(request())
        #expect(result.images.first?.width == 1024)
        await service.shutdown()
    }

    /// A server that reports a sampling step every 50 ms for 15 seconds, recording when a write
    /// fails because the client went away. (grpc-swift 2 servers learn of a cancelled RPC when
    /// they next write, as the Draw Things server does when it sends the next step.)
    final class Flag: Sendable {
        private let value = Mutex(false)
        func set() { value.withLock { $0 = true } }
        var isSet: Bool { value.withLock { $0 } }
    }

    private func slowServer() async throws -> (FakeDrawThingsServer, Flag) {
        let aborted = Flag()
        let server = try await FakeDrawThingsServer { _, writer in
            do {
                for step: Int32 in 1...300 {
                    try await writer.write(FakeResponses.sampling(step))
                    try await Task.sleep(for: .milliseconds(50))
                }
            } catch {
                aborted.set()
                throw error
            }
        }
        return (server, aborted)
    }

    private func waitForAbort(_ aborted: Flag) async throws -> Bool {
        for _ in 0..<40 where !aborted.isSet {
            try await Task.sleep(for: .milliseconds(100))
        }
        return aborted.isSet
    }

    @Test func cancellingGenerateCancelsOnTheServer() async throws {
        let (server, aborted) = try await slowServer()
        defer { Task { await server.stop() } }
        let service = server.makeService()

        let started = Date()
        let task = Task { try await service.generate(request()) }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(Date().timeIntervalSince(started) < 5)
        #expect(try await waitForAbort(aborted))
        await service.shutdown()
    }

    @Test func leavingTheStreamLoopCancelsOnTheServer() async throws {
        let (server, aborted) = try await slowServer()
        defer { Task { await server.stop() } }
        let service = server.makeService()

        var steps = 0
        for try await event in service.stream(request()) {
            if case .progress = event { steps += 1 }
            if steps == 3 { break }
        }
        #expect(steps == 3)
        #expect(try await waitForAbort(aborted))
        await service.shutdown()
    }

    /// As the Draw Things server does when generation fails on its side: previews, then a final
    /// message without images. A preview must not be passed off as the result.
    @Test func emptyResultIsAnError() async throws {
        let preview = try FakeResponses.imageTensor(width: 64, height: 64)
        let server = try await FakeDrawThingsServer { _, writer in
            try await writer.write(FakeResponses.textEncoded)
            try await writer.write(FakeResponses.sampling(1))
            try await writer.write(FakeResponses.preview(preview))
            try await writer.write(ImageGenerationResponse.with { $0.chunkState = .lastChunk })
        }
        defer { Task { await server.stop() } }
        let service = server.makeService()
        await #expect {
            try await service.generate(request())
        } throws: { error in
            if case DrawThingsError.incompleteResponse = error { return true }
            return false
        }
        await service.shutdown()
    }

    @Test func requestCarriesInputsSpecsAndIdentity() async throws {
        let image = try FakeResponses.imageTensor(width: 64, height: 64)
        let server = try await FakeDrawThingsServer { _, writer in
            try await writer.write(ImageGenerationResponse.with { $0.generatedImages = [image] })
        }
        defer { Task { await server.stop() } }
        let service = server.makeService(options: ConnectionOptions(
            security: .plaintext,
            sharedSecret: "s3cret",
            clientIdentity: ClientIdentity(user: "Tester", device: .tablet)
        ))

        var configuration = DrawThingsConfiguration(width: 64, height: 64, steps: 3, model: Self.bundledModel)
        configuration.loras = [LoRAConfig(file: "custom_lora.safetensors", weight: 0.5)]
        let pixels = try ImageHelpers.dtTensorToCGImage(try FakeResponses.imageTensor(width: 64, height: 64))
        var request = request(configuration)
        request.image = pixels
        request.mask = pixels
        _ = try await service.generate(request)

        let sent = try #require(server.record.generateRequests.first)
        #expect(sent.user == "Tester")
        #expect(sent.device == .tablet)
        #expect(sent.sharedSecret == "s3cret")
        #expect(sent.chunked)
        // Content-addressed inputs: image and mask are SHA-256 references into `contents`.
        let hashes = Set(sent.contents.map { Data(SHA256.hash(data: $0)) })
        #expect(hashes.contains(sent.image))
        #expect(hashes.contains(sent.mask))
        #expect(sent.contents.count == 2)
        // Specs for the model (bundled) and a synthetic spec for the unknown LoRA.
        let models = try JSONSerialization.jsonObject(with: sent.override.models) as? [[String: Any]]
        let loras = try JSONSerialization.jsonObject(with: sent.override.loras) as? [[String: Any]]
        #expect(models?.first?["file"] as? String == Self.bundledModel)
        #expect(loras?.first?["file"] as? String == "custom_lora.safetensors")
        #expect(server.record.echoRequests.first?.sharedSecret == "s3cret")
        await service.shutdown()
    }

    @Test func serverEchoSpecsAreUsedForUnknownModels() async throws {
        let server = try await FakeDrawThingsServer(echoReply: EchoReply.with {
            $0.override = .with { $0.models = Data(#"[{"file":"server_only.ckpt","version":"sdxlBase"}]"#.utf8) }
        })
        defer { Task { await server.stop() } }
        let service = server.makeService()
        _ = try? await service.generate(request(DrawThingsConfiguration(width: 64, height: 64, model: "server_only.ckpt")))  // no images sent
        let sent = try #require(server.record.generateRequests.first)
        let models = try JSONSerialization.jsonObject(with: sent.override.models) as? [[String: Any]]
        #expect(models?.first?["version"] as? String == "sdxlBase")
        await service.shutdown()
    }

    @Test func missingSharedSecretIsUnauthenticated() async throws {
        let server = try await FakeDrawThingsServer(echoReply: EchoReply.with { $0.sharedSecretMissing = true })
        defer { Task { await server.stop() } }
        let service = server.makeService()
        await #expect {
            try await service.echo()
        } throws: { error in
            if case DrawThingsError.unauthenticated = error { return true }
            return false
        }
        await service.shutdown()
    }

    @Test func serverErrorsAreMapped() async throws {
        let server = try await FakeDrawThingsServer { _, _ in
            throw RPCError(code: .internalError, message: "out of memory")
        }
        defer { Task { await server.stop() } }
        let service = server.makeService()
        await #expect {
            try await service.generate(request())
        } throws: { error in
            if case DrawThingsError.server(_, let message) = error { return message == "out of memory" }
            return false
        }
        await service.shutdown()
    }

    @Test func truncatedChunkedTensorIsReported() async throws {
        let image = try FakeResponses.imageTensor(width: 64, height: 64)
        let server = try await FakeDrawThingsServer { _, writer in
            try await writer.write(FakeResponses.chunked(image: image, chunkSize: 5_000)[0])  // then stop
        }
        defer { Task { await server.stop() } }
        let service = server.makeService()
        await #expect {
            try await service.generate(request())
        } throws: { error in
            if case DrawThingsError.incompleteResponse = error { return true }
            return false
        }
        await service.shutdown()
    }

    @Test func invalidConfigurationFailsBeforeSending() async throws {
        let server = try await FakeDrawThingsServer()
        defer { Task { await server.stop() } }
        let service = server.makeService()
        await #expect(throws: DrawThingsError.self) {
            try await service.generate(request(DrawThingsConfiguration(width: 16, height: 64, model: Self.bundledModel)))
        }
        #expect(server.record.generateRequests.isEmpty)
        await service.shutdown()
    }

    @Test func filesExistRoundTrip() async throws {
        let server = try await FakeDrawThingsServer()
        defer { Task { await server.stop() } }
        let service = server.makeService()
        let reply = try await service.checkFilesExist(files: ["a.ckpt", "missing.ckpt"])
        #expect(reply.existences == [true, false])
        await service.shutdown()
    }

    @Test @MainActor func sessionMirrorsTheStream() async throws {
        let image = try FakeResponses.imageTensor(width: 64, height: 64)
        let server = try await FakeDrawThingsServer { _, writer in
            try await writer.write(FakeResponses.sampling(2))
            try await writer.write(FakeResponses.preview(image))
            try await writer.write(ImageGenerationResponse.with { $0.generatedImages = [image] })
        }
        defer { Task { await server.stop() } }
        let session = DrawThingsSession(service: server.makeService())
        await session.connect()
        #expect(session.isConnected)
        #expect(session.serverInfo?.message == "HELLO test")

        let result = try await session.generate(request())
        #expect(result.images.count == 1)
        #expect(session.lastResult?.id == result.id)
        #expect(!session.isGenerating)
        #expect(session.progress == nil)
        #expect(session.preview == nil)
    }
}
