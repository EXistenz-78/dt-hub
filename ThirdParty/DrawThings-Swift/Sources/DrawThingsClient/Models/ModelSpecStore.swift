//
//  ModelSpecStore.swift
//  DrawThingsClient
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import Foundation

/// One model or LoRA specification, kept as the raw snake_case JSON object that Draw Things
/// servers decode from `MetadataOverride`.
public struct ModelSpec: Sendable, Hashable {
    /// The model file name the spec describes.
    public let file: String
    /// The spec's model version string (for example `"flux2"`), when present.
    public let version: String?
    /// The spec as a JSON object.
    public let json: Data
    /// Files of additional models this model runs with (for example Stable Cascade stage B).
    public let stageModels: [String]
    /// The model's own video frame rate, when its spec sets one (`frames_per_second`).
    public let framesPerSecond: Double?

    /// Creates a spec from a JSON object. Returns nil if the object has no `file` key.
    public init?(json: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        self.init(object: object)
    }

    init?(object: [String: Any]) {
        guard let file = object["file"] as? String,
              let json = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        else { return nil }
        self.file = file
        self.version = object["version"] as? String
        self.stageModels = object["stage_models"] as? [String] ?? []
        self.framesPerSecond = (object["frames_per_second"] as? NSNumber)?.doubleValue
        self.json = json
    }

    /// Parses a JSON array of spec objects, skipping entries without a `file`.
    static func parseArray(_ data: Data) -> [String: ModelSpec] {
        guard !data.isEmpty,
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [:] }
        var specs = [String: ModelSpec]()
        for object in array {
            if let spec = ModelSpec(object: object) { specs[spec.file] = spec }
        }
        return specs
    }

    /// Encodes specs as the JSON array `MetadataOverride` expects.
    static func encodeArray(_ specs: [ModelSpec]) -> Data {
        var data = Data("[".utf8)
        for (index, spec) in specs.enumerated() {
            if index > 0 { data.append(UInt8(ascii: ",")) }
            data.append(spec.json)
        }
        data.append(UInt8(ascii: "]"))
        return data
    }
}

/// Resolves the model specifications sent to the server in each generation request.
///
/// Without the right specification a Draw Things server falls back to SD v1 defaults
/// and produces noise, so the store looks a model up in this order:
/// 1. specs the app registered with ``register(_:)``
/// 2. the live Draw Things model list, when ``ModelSpecSource/bundledAndRemote(_:)`` is enabled
/// 3. the snapshot bundled with this package (refreshed at release time)
/// 4. the specs the server reported in its echo reply
public actor ModelSpecStore {
    /// Fetches the remote model list. Replaceable for tests.
    typealias Fetcher = @Sendable (URL) async throws -> Data

    private let source: ModelSpecSource
    private let fetcher: Fetcher
    private var registered: [String: ModelSpec] = [:]
    private var remote: [String: ModelSpec] = [:]
    private var server: [String: ModelSpec] = [:]
    private var remoteFetch: Task<Void, Error>?
    private var remoteFetched = false

    public init(source: ModelSpecSource = .bundled) {
        self.init(source: source, fetcher: ModelSpecStore.defaultFetcher)
    }

    init(source: ModelSpecSource, fetcher: @escaping Fetcher) {
        self.source = source
        self.fetcher = fetcher
    }

    // MARK: - Sources

    /// Registers specs the app knows about (for example custom models imported into Draw
    /// Things). Registered specs take priority over every other source.
    public func register(_ specs: [ModelSpec]) {
        for spec in specs { registered[spec.file] = spec }
    }

    /// Records the model specs a server reported in its echo reply.
    func ingestServerOverride(_ override: MetadataOverride) {
        server = ModelSpec.parseArray(override.models)
    }

    /// The snapshot of `models.json` bundled with this package.
    static let bundled: [String: ModelSpec] = {
        guard let url = Bundle.module.url(forResource: "models", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            DTLogger.warning("models.json not found in bundle", category: .models)
            return [:]
        }
        return ModelSpec.parseArray(data)
    }()

    // MARK: - Lookup

    /// The spec for a model or LoRA file, fetching the remote list first when it is enabled
    /// and the file is not otherwise known.
    public func spec(for file: String) async -> ModelSpec? {
        if let spec = localSpec(for: file) { return spec }
        await fetchRemoteIfNeeded()
        return localSpec(for: file) ?? server[file]
    }

    private func localSpec(for file: String) -> ModelSpec? {
        registered[file] ?? remote[file] ?? Self.bundled[file]
    }

    /// Builds the override for a request, mirroring the Draw Things app's
    /// `ImageGeneratorUtils.metadataOverride`: specs for the model, its stage models and the
    /// refiner, plus a spec for each LoRA, merged into `base` (normally the server's echo
    /// override, which carries control nets, textual inversions and upscalers). Returns `base`
    /// unchanged when the model is unknown.
    ///
    /// LoRAs without a known spec get a minimal synthetic one using the model's version,
    /// because the server silently skips any LoRA missing from its override mapping.
    func override(
        forModel modelFile: String,
        refinerModel: String? = nil,
        loraFiles: [String],
        base: MetadataOverride?
    ) async -> MetadataOverride? {
        guard let modelSpec = await spec(for: modelFile) else {
            DTLogger.debug("No spec found for \(modelFile), using server metadata", category: .models)
            return base
        }
        var modelSpecs = [modelSpec]
        if let refinerModel, !refinerModel.isEmpty, let refinerSpec = await spec(for: refinerModel) {
            modelSpecs.append(refinerSpec)
        }
        // Each model is followed by its stage models, as upstream does.
        var ordered = [ModelSpec]()
        for spec in modelSpecs where !ordered.contains(where: { $0.file == spec.file }) {
            ordered.append(spec)
            for stageModel in spec.stageModels where !ordered.contains(where: { $0.file == stageModel }) {
                if let stageSpec = await self.spec(for: stageModel) { ordered.append(stageSpec) }
            }
        }
        modelSpecs = ordered

        let version = modelSpec.version ?? "v1"
        var loraSpecs = [ModelSpec]()
        for lora in loraFiles {
            if let spec = await spec(for: lora) {
                loraSpecs.append(spec)
            } else if let synthetic = ModelSpec(object: ["file": lora, "name": lora, "prefix": "", "version": version]) {
                loraSpecs.append(synthetic)
            }
        }
        var merged = base ?? MetadataOverride()
        merged.models = ModelSpec.encodeArray(modelSpecs)
        merged.loras = loraSpecs.isEmpty ? Data() : ModelSpec.encodeArray(loraSpecs)
        DTLogger.debug("Using specs for \(modelSpecs.map(\.file)) (version \(version)), loras: \(loraFiles)", category: .models)
        return merged
    }

    // MARK: - Remote fetch

    /// Downloads the live model list once. Concurrent callers await the same download; a failed
    /// download is retried on the next lookup.
    private func fetchRemoteIfNeeded() async {
        guard case .bundledAndRemote(let url) = source, !remoteFetched else { return }
        let task: Task<Void, Error>
        if let inFlight = remoteFetch {
            task = inFlight
        } else {
            let fetcher = self.fetcher
            task = Task { [weak self] in
                let data = try await fetcher(url)
                await self?.storeRemote(ModelSpec.parseArray(data))
            }
            remoteFetch = task
        }
        do {
            try await task.value
        } catch {
            DTLogger.warning("Failed to fetch remote model specs: \(error.localizedDescription)", category: .models)
        }
        remoteFetch = nil
    }

    private func storeRemote(_ specs: [String: ModelSpec]) {
        remote = specs
        remoteFetched = true
        DTLogger.debug("Fetched \(specs.count) model specs from remote list", category: .models)
    }

    private static let defaultFetcher: Fetcher = { url in
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
