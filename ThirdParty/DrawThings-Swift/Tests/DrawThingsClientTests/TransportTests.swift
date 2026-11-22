import Foundation
import Synchronization
import Testing
@testable import DrawThingsClient

@Suite("ServerEndpoint")
struct ServerEndpointTests {
    @Test(arguments: [
        ("localhost", "localhost", 7859),
        ("192.168.1.20:7860", "192.168.1.20", 7860),
        ("studio.local", "studio.local", 7859),
        ("  grpc://example.com:443/ ", "example.com", 443),
        ("[fe80::1]:7859", "fe80::1", 7859),
        ("[::1]", "::1", 7859),
        ("::1", "::1", 7859),
        ("2001:db8::7", "2001:db8::7", 7859),
    ])
    func parses(address: String, host: String, port: Int) throws {
        let endpoint = try ServerEndpoint(address)
        #expect(endpoint.host == host)
        #expect(endpoint.port == port)
    }

    @Test(arguments: ["", "   ", "host:", "host:0", "host:70000", "host:abc", "[::1", "[]:7859", ":7859"])
    func rejects(address: String) {
        #expect(throws: ServerEndpointError.self) { try ServerEndpoint(address) }
    }

    @Test func descriptionBracketsIPv6() throws {
        #expect(try ServerEndpoint("[fe80::1]:99").description == "[fe80::1]:99")
        #expect(try ServerEndpoint("host:99").description == "host:99")
    }

    @Test(arguments: [
        "localhost", "127.0.0.1", "::1", "10.0.0.5", "172.20.1.1", "192.168.0.10",
        "169.254.3.4", "100.100.1.1", "fd12::1", "fe80::1", "mac-studio.local", "macstudio",
    ])
    func localNetworkHosts(host: String) {
        #expect(ServerEndpoint(host: host).isLocalNetwork)
    }

    @Test(arguments: ["example.com", "8.8.8.8", "172.32.0.1", "100.128.0.1", "2001:db8::7"])
    func publicHosts(host: String) {
        #expect(!ServerEndpoint(host: host).isLocalNetwork)
    }

    @Test func classifiesIPLiterals() {
        #expect(ServerEndpoint(host: "192.168.68.67").isIPv4Literal)
        #expect(!ServerEndpoint(host: "192.168.68").isIPv4Literal)
        #expect(!ServerEndpoint(host: "256.1.1.1").isIPv4Literal)
        #expect(!ServerEndpoint(host: "molly.example.com").isIPv4Literal)
        #expect(ServerEndpoint(host: "fe80::1").isIPv6Literal)
    }

    @Test func resolvesLiteralsWithoutLookup() async {
        #expect(await ServerEndpoint(host: "10.0.0.1").resolveAddresses() == ["10.0.0.1"])
        #expect(await ServerEndpoint(host: "::1").resolveAddresses() == ["::1"])
    }

    @Test func resolvesLocalhostToLoopback() async {
        let addresses = await ServerEndpoint(host: "localhost").resolveAddresses()
        #expect(!addresses.isEmpty)
        #expect(addresses.allSatisfy { ServerEndpoint(host: $0).isLoopback })
    }
}

@Suite("ResponseAssembler")
struct ResponseAssemblerTests {
    private func response(images: [Data] = [], audio: [Data] = [], state: ChunkState) -> ImageGenerationResponse {
        ImageGenerationResponse.with {
            $0.generatedImages = images
            $0.generatedAudio = audio
            $0.chunkState = state
        }
    }

    @Test func unchunkedImagesPassThrough() {
        var assembler = ResponseAssembler()
        let output = assembler.consume(response(images: [Data([1, 2])], state: .lastChunk))
        #expect(output.images == [Data([1, 2])])
        #expect(!assembler.hasIncompleteTensor)
    }

    @Test func chunkedImageIsReassembled() {
        var assembler = ResponseAssembler()
        #expect(assembler.consume(response(images: [Data([1, 2])], state: .moreChunks)).images.isEmpty)
        #expect(assembler.consume(response(images: [Data([3])], state: .moreChunks)).images.isEmpty)
        #expect(assembler.hasIncompleteTensor)
        let output = assembler.consume(response(images: [Data([4, 5])], state: .lastChunk))
        #expect(output.images == [Data([1, 2, 3, 4, 5])])
        #expect(!assembler.hasIncompleteTensor)
    }

    @Test func batchOfImagesArrivesOnePerMessage() {
        var assembler = ResponseAssembler()
        var images: [Data] = []
        for byte: UInt8 in 1...3 {
            images += assembler.consume(response(images: [Data([byte])], state: .lastChunk)).images
        }
        #expect(images == [Data([1]), Data([2]), Data([3])])
    }

    @Test func audioIsReassembledIndependently() {
        var assembler = ResponseAssembler()
        _ = assembler.consume(response(audio: [Data([9])], state: .moreChunks))
        let output = assembler.consume(response(audio: [Data([8])], state: .lastChunk))
        #expect(output.audio == [Data([9, 8])])
        #expect(output.images.isEmpty)
    }
}

@Suite("ModelSpecStore")
struct ModelSpecStoreTests {
    private static func specsJSON(_ entries: [(file: String, version: String)]) -> Data {
        let array = entries.map { ["file": $0.file, "version": $0.version, "name": $0.file] }
        return try! JSONSerialization.data(withJSONObject: array)
    }

    private static let remoteURL = URL(string: "https://example.invalid/models.json")!

    @Test func bundledSnapshotIsLoaded() {
        #expect(!ModelSpecStore.bundled.isEmpty)
    }

    @Test func bundledSourceNeverFetches() async {
        let calls = Mutex(0)
        let store = ModelSpecStore(source: .bundled) { _ in
            calls.withLock { $0 += 1 }
            return Data()
        }
        #expect(await store.spec(for: "not_a_real_model.ckpt") == nil)
        #expect(calls.withLock { $0 } == 0)
    }

    @Test func concurrentLookupsShareOneFetch() async {
        let calls = Mutex(0)
        let store = ModelSpecStore(source: .bundledAndRemote(Self.remoteURL)) { _ in
            calls.withLock { $0 += 1 }
            try await Task.sleep(for: .milliseconds(50))
            return Self.specsJSON([("remote_model.ckpt", "flux2")])
        }
        let results = await withTaskGroup(of: ModelSpec?.self) { group in
            for _ in 0..<5 { group.addTask { await store.spec(for: "remote_model.ckpt") } }
            return await group.reduce(into: [ModelSpec?]()) { $0.append($1) }
        }
        #expect(results.allSatisfy { $0?.version == "flux2" })
        #expect(calls.withLock { $0 } == 1)
    }

    @Test func failedFetchIsRetried() async {
        let calls = Mutex(0)
        let store = ModelSpecStore(source: .bundledAndRemote(Self.remoteURL)) { _ in
            let attempt = calls.withLock { $0 += 1; return $0 }
            if attempt == 1 { throw URLError(.notConnectedToInternet) }
            return Self.specsJSON([("remote_model.ckpt", "flux2")])
        }
        #expect(await store.spec(for: "remote_model.ckpt") == nil)
        #expect(await store.spec(for: "remote_model.ckpt")?.version == "flux2")
        #expect(calls.withLock { $0 } == 2)
    }

    @Test func registeredSpecsTakePriority() async throws {
        let store = ModelSpecStore(source: .bundled) { _ in Data() }
        let bundledFile = try #require(ModelSpecStore.bundled.keys.first)
        let custom = try #require(ModelSpec(json: Self.specsJSON([(bundledFile, "custom")]).dropFirst().dropLast()))
        await store.register([custom])
        #expect(await store.spec(for: bundledFile)?.version == "custom")
    }

    @Test func serverSpecsAreTheFallback() async {
        let store = ModelSpecStore(source: .bundled) { _ in Data() }
        await store.ingestServerOverride(MetadataOverride.with {
            $0.models = Self.specsJSON([("server_only.ckpt", "sdxlBase")])
        })
        #expect(await store.spec(for: "server_only.ckpt")?.version == "sdxlBase")
    }

    @Test func overrideIncludesModelAndSyntheticLoRASpecs() async throws {
        let store = ModelSpecStore(source: .bundled) { _ in Data() }
        await store.register([try #require(ModelSpec(json: Data(#"{"file":"m.ckpt","version":"flux2"}"#.utf8)))])
        let base = MetadataOverride.with { $0.controlNets = Data("[1]".utf8) }

        let override = try #require(await store.override(forModel: "m.ckpt", loraFiles: ["my_lora.safetensors"], base: base))

        let models = try JSONSerialization.jsonObject(with: override.models) as? [[String: Any]]
        let loras = try JSONSerialization.jsonObject(with: override.loras) as? [[String: Any]]
        #expect(models?.first?["file"] as? String == "m.ckpt")
        #expect(loras?.first?["file"] as? String == "my_lora.safetensors")
        #expect(loras?.first?["version"] as? String == "flux2")
        #expect(override.controlNets == base.controlNets, "server metadata for other kinds is kept")
    }

    @Test func overrideIncludesStageAndRefinerModels() async throws {
        let store = ModelSpecStore(source: .bundled) { _ in Data() }
        await store.register([
            try #require(ModelSpec(json: Data(#"{"file":"c.ckpt","version":"wurstchenStageC","stage_models":["b.ckpt"]}"#.utf8))),
            try #require(ModelSpec(json: Data(#"{"file":"b.ckpt","version":"wurstchenStageB"}"#.utf8))),
            try #require(ModelSpec(json: Data(#"{"file":"r.ckpt","version":"sdxlRefiner"}"#.utf8))),
        ])
        let override = try #require(await store.override(forModel: "c.ckpt", refinerModel: "r.ckpt", loraFiles: [], base: nil))
        let models = try JSONSerialization.jsonObject(with: override.models) as? [[String: Any]]
        #expect(models?.compactMap { $0["file"] as? String } == ["c.ckpt", "b.ckpt", "r.ckpt"])
    }

    @Test func unknownModelKeepsServerMetadata() async {
        let store = ModelSpecStore(source: .bundled) { _ in Data() }
        let base = MetadataOverride.with { $0.models = Data("[]".utf8) }
        #expect(await store.override(forModel: "unknown.ckpt", loraFiles: [], base: base) == base)
    }
}

@Suite("DrawThingsService helpers")
struct ServiceHelperTests {
    @Test func readsModelAndLoRAFilesFromConfiguration() throws {
        var configuration = DrawThingsConfiguration(model: "flux_2_klein_4b_q8p.ckpt", refinerModel: "refiner.ckpt")
        configuration.loras = [LoRAConfig(file: "a.ckpt"), LoRAConfig(file: "b.ckpt")]
        let files = try DrawThingsService.modelFiles(in: configuration.toFlatBufferData())
        #expect(files.model == "flux_2_klein_4b_q8p.ckpt")
        #expect(files.refiner == "refiner.ckpt")
        #expect(files.loras == ["a.ckpt", "b.ckpt"])
    }

    @Test func rejectsInvalidConfigurationBytes() {
        #expect(throws: DrawThingsError.self) {
            try DrawThingsService.modelFiles(in: Data([0xFF, 0xFF, 0xFF, 0xFF, 1, 2]))
        }
    }
}
