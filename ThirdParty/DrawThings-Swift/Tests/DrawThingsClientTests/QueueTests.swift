import Foundation
import GRPCCore
import Synchronization
import Testing
@testable import DrawThingsClient
@testable import DrawThingsQueue

/// ``GenerationQueue`` against the in-process gRPC server.
@Suite("GenerationQueue")
@MainActor
struct QueueTests {
    static let model = ServerIntegrationTests.bundledModel

    private func request(_ prompt: String) -> GenerationRequest {
        GenerationRequest(prompt: prompt, configuration: DrawThingsConfiguration(width: 64, height: 64, steps: 3, model: Self.model))
    }

    /// A server that returns one image, after 300 sampling steps 50 ms apart for "slow" prompts.
    private func server(failing: (@Sendable (String) -> Bool)? = nil) async throws -> FakeDrawThingsServer {
        let image = try FakeResponses.imageTensor(width: 64, height: 64)
        return try await FakeDrawThingsServer { request, writer in
            if failing?(request.prompt) == true {
                throw RPCError(code: .internalError, message: "out of memory")
            }
            if request.prompt.hasPrefix("slow") {
                for step: Int32 in 1...300 {
                    try await writer.write(FakeResponses.sampling(step))
                    try await Task.sleep(for: .milliseconds(50))
                }
            }
            try await writer.write(FakeResponses.sampling(1))
            try await writer.write(ImageGenerationResponse.with { $0.generatedImages = [image] })
        }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, timeout: Duration = .seconds(10)) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("timed out waiting")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func idle(_ queue: GenerationQueue) -> Bool {
        queue.current == nil && queue.pending.isEmpty
    }

    @Test func runsJobsInOrderAndAssignsSeeds() async throws {
        let server = try await server()
        defer { Task { await server.stop() } }
        let queue = GenerationQueue(service: server.makeService())
        let results = queue.results

        queue.enqueue(contentsOf: ["a", "b", "c"].map(request))
        var prompts: [String] = []
        for await result in results {
            prompts.append(result.request.prompt)
            if prompts.count == 3 { break }
        }

        #expect(prompts == ["a", "b", "c"])
        #expect(server.record.generateRequests.map(\.prompt) == ["a", "b", "c"])
        #expect(queue.finished.map(\.status) == [.completed, .completed, .completed])
        #expect(queue.finished.allSatisfy { $0.request.configuration.seed != nil && $0.result?.images.count == 1 })
        #expect(queue.finished.allSatisfy { ($0.duration ?? -1) >= 0 })
        #expect(idle(queue))
        await queue.service.shutdown()
    }

    @Test func eventsFollowTheJob() async throws {
        let server = try await server()
        defer { Task { await server.stop() } }
        let queue = GenerationQueue(service: server.makeService())
        let events = queue.events

        let job = queue.enqueue(request("a"), name: "First")
        var labels: [String] = []
        for await event in events {
            switch event {
            case .added(let added): labels.append("added \(added.name)")
            case .started: labels.append("started")
            case .progress(let id, _): if labels.last != "progress" { labels.append("progress") }; #expect(id == job.id)
            case .completed(let completed): labels.append("completed \(completed.status)")
            default: labels.append("other")
            }
            if labels.last?.hasPrefix("completed") == true { break }
        }
        #expect(labels == ["added First", "started", "progress", "completed completed"])
        await queue.service.shutdown()
    }

    @Test func pauseHoldsJobsUntilResumed() async throws {
        let server = try await server()
        defer { Task { await server.stop() } }
        let queue = GenerationQueue(service: server.makeService())

        queue.pause()
        queue.enqueue(contentsOf: [request("a"), request("b")])
        try await Task.sleep(for: .milliseconds(200))
        #expect(server.record.generateRequests.isEmpty)
        #expect(queue.pending.count == 2)

        queue.resume()
        try await waitUntil { queue.finished.count == 2 }
        #expect(!queue.isPaused)
        await queue.service.shutdown()
    }

    @Test func failedJobsCanBeRetried() async throws {
        let attempts = Mutex(0)
        let server = try await server(failing: { _ in
            attempts.withLock { $0 += 1; return $0 == 1 }  // only the first attempt fails
        })
        defer { Task { await server.stop() } }
        let queue = GenerationQueue(service: server.makeService())
        queue.maxRetries = 1

        let job = queue.enqueue(request("a"))
        try await waitUntil { queue.finished.count == 1 }
        let failed = try #require(queue.job(job.id))
        #expect(failed.status == .failed)
        #expect((failed.error as? DrawThingsError).map { if case .server = $0 { true } else { false } } == true)
        #expect(queue.canRetry(job.id))

        #expect(queue.retry(job.id))
        try await waitUntil { queue.job(job.id)?.status == .completed }
        #expect(queue.job(job.id)?.retryCount == 1)
        #expect(!queue.canRetry(job.id))
        #expect(!queue.retry(job.id))
        await queue.service.shutdown()
    }

    @Test func lostConnectionPausesAndKeepsTheJob() async throws {
        // Port 1 on loopback refuses connections.
        let unreachable = DrawThingsService(
            endpoint: ServerEndpoint(host: "127.0.0.1", port: 1),
            options: ConnectionOptions(security: .plaintext, requestTimeout: .seconds(5))
        )
        let queue = GenerationQueue(service: unreachable)
        let job = queue.enqueue(request("a"))
        try await waitUntil { queue.isPaused }
        #expect(queue.pending.map(\.id) == [job.id])
        #expect(queue.pending.first?.status == .pending)
        #expect(queue.pauseReason?.hasPrefix("Connection lost") == true)
        #expect(queue.finished.isEmpty)

        let server = try await server()
        defer { Task { await server.stop() } }
        queue.service = server.makeService()
        queue.resume()
        try await waitUntil { queue.job(job.id)?.status == .completed }
        await unreachable.shutdown()
        await queue.service.shutdown()
    }

    @Test func cancelsPendingAndRunningJobs() async throws {
        let server = try await server()
        defer { Task { await server.stop() } }
        let queue = GenerationQueue(service: server.makeService())

        let slow = queue.enqueue(request("slow"))
        let skipped = queue.enqueue(request("skipped"))
        let last = queue.enqueue(request("last"))
        try await waitUntil { queue.progress?.step != nil }

        #expect(queue.cancel(skipped.id))
        #expect(queue.job(skipped.id)?.status == .cancelled)
        #expect(queue.cancel(slow.id))
        try await waitUntil { queue.job(last.id)?.status == .completed }

        #expect(queue.job(slow.id)?.status == .cancelled)
        #expect(server.record.generateRequests.map(\.prompt) == ["slow", "last"])
        #expect(!queue.cancel(last.id))  // already finished
        await queue.service.shutdown()
    }

    @Test func pendingJobsCanBeReorderedAndRemoved() throws {
        let queue = GenerationQueue(service: try DrawThingsService(address: "127.0.0.1:1"))
        queue.pause()
        let jobs = queue.enqueue(contentsOf: ["a", "b", "c", "d"].map(request))

        queue.movePending(fromOffsets: [3], toOffset: 0)
        #expect(queue.pending.map(\.request.prompt) == ["d", "a", "b", "c"])
        queue.movePending(fromOffsets: [0, 1], toOffset: 4)
        #expect(queue.pending.map(\.request.prompt) == ["b", "c", "d", "a"])

        queue.remove(jobs[1].id)
        #expect(queue.pending.map(\.request.prompt) == ["c", "d", "a"])
        queue.cancelAll()
        #expect(queue.pending.isEmpty)
        #expect(queue.finished.map(\.status) == [.cancelled, .cancelled, .cancelled])
        queue.clearFinished()
        #expect(queue.jobs.isEmpty)
    }

    @Test func finishedJobsAreTrimmed() throws {
        let queue = GenerationQueue(service: try DrawThingsService(address: "127.0.0.1:1"))
        queue.pause()
        queue.enqueue(contentsOf: ["a", "b", "c"].map(request))
        queue.maxFinishedJobs = 2
        queue.cancelAll()
        #expect(queue.finished.map(\.request.prompt) == ["b", "c"])
    }

    @Test func jobNamesComeFromThePrompt() {
        #expect(QueueJob.name(fromPrompt: "  ") == "Untitled")
        #expect(QueueJob.name(fromPrompt: "short prompt") == "short prompt")
        let long = String(repeating: "word ", count: 20)
        #expect(QueueJob.name(fromPrompt: long) == String(repeating: "word ", count: 9) + "word...")
    }

    // MARK: - Persistence

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "queue-\(UUID().uuidString).json")
    }

    @Test func pendingJobsAreSavedWhole() async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let storage = QueueStorage(fileURL: url)
        let queue = GenerationQueue(service: try DrawThingsService(address: "127.0.0.1:1"), storage: storage)
        queue.pause()

        let pixels = try ImageHelpers.dtTensorToCGImage(try FakeResponses.imageTensor(width: 64, height: 64))
        var request = request("saved")
        request.negativePrompt = "blurry"
        request.image = pixels
        request.mask = pixels
        request.hints = [HintProto.with { $0.hintType = "depth"; $0.tensors = [.with { $0.tensor = Data([1, 2, 3]); $0.weight = 0.5 }] }]
        request.override = MetadataOverride.with { $0.models = Data("[]".utf8) }
        request.modelFamily = .minimaxH3
        request.audioSampleRate = 32_000
        request.configuration.loras = [LoRAConfig(file: "style.safetensors", weight: 0.7)]
        let job = queue.enqueue(request, name: "Named")

        var saved: [QueueJob] = []
        for _ in 0..<100 where saved.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
            saved = (try? await storage.load()) ?? []
        }
        let restored = try #require(saved.first)
        #expect(saved.count == 1)
        #expect(restored.id == job.id)
        #expect(restored.name == "Named")
        #expect(abs(restored.createdAt.timeIntervalSince(job.createdAt)) < 1)
        #expect(restored.status == .pending)
        #expect(restored.request.prompt == "saved")
        #expect(restored.request.negativePrompt == "blurry")
        #expect(restored.request.configuration == job.request.configuration)  // including the assigned seed
        #expect(restored.request.image?.width == 64)
        #expect(restored.request.mask?.height == 64)
        #expect(restored.request.hints == request.hints)
        #expect(restored.request.override == request.override)
        #expect(restored.request.modelFamily == .minimaxH3)
        #expect(restored.request.audioSampleRate == 32_000)

        // A new queue picks the job up.
        let relaunched = GenerationQueue(service: try DrawThingsService(address: "127.0.0.1:1"), storage: storage)
        relaunched.pause()
        try await relaunched.restore()
        #expect(relaunched.pending.map(\.id) == [job.id])
        try await storage.clear()
        #expect(try await storage.load().isEmpty)
    }

    @Test func readsDrawThingsQueueZeroFiles() async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        // As written by DrawThingsQueue 0.1 (abridged: missing keys keep their defaults).
        let legacy = """
        [{
          "id": "8C7D2B0E-2F5A-4C1B-9E6D-3A4B5C6D7E8F",
          "prompt": "a cat", "negativePrompt": "dog", "name": "Cat",
          "createdAt": "2026-03-16T10:00:00Z",
          "configuration": {
            "width": 768, "height": 512, "steps": 20, "model": "flux_1_dev_q8p.ckpt", "sampler": 10,
            "guidanceScale": 3.5, "seed": 1234, "seedMode": 2, "compressionArtifacts": 3,
            "colorCalibration": 1, "causalInferenceEnabled": false, "causalInference": 3,
            "configName": "Portrait", "refinerModel": null, "numFrames": 14,
            "loras": [{"file": "style.safetensors", "weight": 0.6, "mode": 1}],
            "controls": [{"file": "depth.ckpt", "weight": 1, "guidanceStart": 0, "guidanceEnd": 1, "controlMode": 2}]
          }
        }]
        """
        try Data(legacy.utf8).write(to: url)

        let jobs = try await QueueStorage(fileURL: url).load()
        let job = try #require(jobs.first)
        let configuration = job.request.configuration
        #expect(job.id == UUID(uuidString: "8C7D2B0E-2F5A-4C1B-9E6D-3A4B5C6D7E8F"))
        #expect(job.name == "Cat")
        #expect(job.request.prompt == "a cat")
        #expect(job.request.negativePrompt == "dog")
        #expect(job.createdAt == ISO8601DateFormatter().date(from: "2026-03-16T10:00:00Z"))
        #expect(configuration.width == 768)
        #expect(configuration.model == "flux_1_dev_q8p.ckpt")
        #expect(configuration.sampler.rawValue == 10)
        #expect(configuration.seed == 1234)
        #expect(configuration.seedMode.rawValue == 2)
        #expect(configuration.compressionArtifacts == .jpeg)
        #expect(configuration.colorCalibration == .lab)
        #expect(!configuration.causalInferenceEnabled)
        #expect(configuration.name == "Portrait")
        #expect(configuration.refinerModel == nil)
        #expect(configuration.loras.first?.mode == .base)
        #expect(configuration.controls.first?.controlMode == .control)
    }
}
