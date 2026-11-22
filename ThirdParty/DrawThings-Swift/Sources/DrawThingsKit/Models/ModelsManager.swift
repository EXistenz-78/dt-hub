//
//  ModelsManager.swift
//  DrawThingsKit
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import DrawThingsClient
import Foundation
import Observation

// MARK: - Model Data Structures

/// Checkpoint (base) model information from the server.
public struct CheckpointModel: Identifiable, Codable, Hashable, Sendable {
    public var id: String { file }
    public let name: String
    public let file: String
    public let version: String?
    public let prefix: String?
    public let modifier: String?
    public let note: String?
    public let defaultScale: Int?
    public let autoencoder: String?
    public let textEncoder: String?
    public let clipEncoder: String?

    /// The source of this model (local, official, or community).
    public var source: ModelSource

    enum CodingKeys: String, CodingKey {
        case name, file, version, prefix, modifier, note, autoencoder, source
        case defaultScale = "default_scale"
        case textEncoder = "text_encoder"
        case clipEncoder = "clip_encoder"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        file = try container.decode(String.self, forKey: .file)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        prefix = try container.decodeIfPresent(String.self, forKey: .prefix)
        modifier = try container.decodeIfPresent(String.self, forKey: .modifier)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        defaultScale = try container.decodeIfPresent(Int.self, forKey: .defaultScale)
        autoencoder = try container.decodeIfPresent(String.self, forKey: .autoencoder)
        textEncoder = try container.decodeIfPresent(String.self, forKey: .textEncoder)
        clipEncoder = try container.decodeIfPresent(String.self, forKey: .clipEncoder)
        source = try container.decodeIfPresent(ModelSource.self, forKey: .source) ?? .local
    }

    public init(
        name: String,
        file: String,
        version: String? = nil,
        prefix: String? = nil,
        modifier: String? = nil,
        note: String? = nil,
        defaultScale: Int? = nil,
        autoencoder: String? = nil,
        textEncoder: String? = nil,
        clipEncoder: String? = nil,
        source: ModelSource = .local
    ) {
        self.name = name
        self.file = file
        self.version = version
        self.prefix = prefix
        self.modifier = modifier
        self.note = note
        self.defaultScale = defaultScale
        self.autoencoder = autoencoder
        self.textEncoder = textEncoder
        self.clipEncoder = clipEncoder
        self.source = source
    }

    /// The model family, from the version (or the file name when there's no version).
    public var family: ModelFamily {
        ModelFamily.detect(from: version ?? file)
    }

    /// The frame rate for video models, or nil for image models. Matches Draw Things; a
    /// generation's `result.media.frameRate` also accounts for the model's own spec.
    public var framesPerSecond: Int? {
        version.flatMap(ModelFamily.frameRate(forVersion:)) ?? ModelFamily.detect(from: file).nativeFrameRate
    }

    /// The sample rate (Hz) of audio this model generates, or nil for models without audio.
    public var audioSampleRate: Int? {
        family.audioSampleRate.map { Int($0) }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(file)
    }

    public static func == (lhs: CheckpointModel, rhs: CheckpointModel) -> Bool {
        lhs.file == rhs.file
    }
}

/// LoRA model information from the server.
public struct LoRAModel: Identifiable, Codable, Hashable, Sendable {
    public var id: String { file }
    public let name: String
    public let file: String
    public let version: String?
    public let prefix: String?
    public let isLoHa: Bool?
    public let isConsistencyModel: Bool?

    /// The source of this model (local, official, or community).
    public var source: ModelSource

    enum CodingKeys: String, CodingKey {
        case name, file, version, prefix, source
        case isLoHa = "is_lo_ha"
        case isConsistencyModel = "is_consistency_model"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        file = try container.decode(String.self, forKey: .file)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        prefix = try container.decodeIfPresent(String.self, forKey: .prefix)
        isLoHa = try container.decodeIfPresent(Bool.self, forKey: .isLoHa)
        isConsistencyModel = try container.decodeIfPresent(Bool.self, forKey: .isConsistencyModel)
        source = try container.decodeIfPresent(ModelSource.self, forKey: .source) ?? .local
    }

    public init(
        name: String,
        file: String,
        version: String? = nil,
        prefix: String? = nil,
        isLoHa: Bool? = nil,
        isConsistencyModel: Bool? = nil,
        source: ModelSource = .local
    ) {
        self.name = name
        self.file = file
        self.version = version
        self.prefix = prefix
        self.isLoHa = isLoHa
        self.isConsistencyModel = isConsistencyModel
        self.source = source
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(file)
    }

    public static func == (lhs: LoRAModel, rhs: LoRAModel) -> Bool {
        lhs.file == rhs.file
    }
}

/// ControlNet model information from the server.
public struct ControlNetModel: Identifiable, Codable, Hashable, Sendable {
    public var id: String { file }
    public let name: String
    public let file: String
    public let version: String?
    public let prefix: String?

    /// The source of this model (local, official, or community).
    public var source: ModelSource

    enum CodingKeys: String, CodingKey {
        case name, file, version, prefix, source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        file = try container.decode(String.self, forKey: .file)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        prefix = try container.decodeIfPresent(String.self, forKey: .prefix)
        source = try container.decodeIfPresent(ModelSource.self, forKey: .source) ?? .local
    }

    public init(
        name: String,
        file: String,
        version: String? = nil,
        prefix: String? = nil,
        source: ModelSource = .local
    ) {
        self.name = name
        self.file = file
        self.version = version
        self.prefix = prefix
        self.source = source
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(file)
    }

    public static func == (lhs: ControlNetModel, rhs: ControlNetModel) -> Bool {
        lhs.file == rhs.file
    }
}

/// Textual Inversion (embedding) model information from the server.
public struct TextualInversionModel: Identifiable, Codable, Hashable, Sendable {
    public var id: String { file }
    public let name: String
    public let file: String
    public let keyword: String?
    public let version: String?
    public let length: Int?
    public let deprecated: Bool?

    /// The source of this model (local, official, or community).
    public var source: ModelSource

    enum CodingKeys: String, CodingKey {
        case name, file, keyword, version, length, deprecated, source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        file = try container.decode(String.self, forKey: .file)
        keyword = try container.decodeIfPresent(String.self, forKey: .keyword)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        length = try container.decodeIfPresent(Int.self, forKey: .length)
        deprecated = try container.decodeIfPresent(Bool.self, forKey: .deprecated)
        source = try container.decodeIfPresent(ModelSource.self, forKey: .source) ?? .local
    }

    public init(
        name: String,
        file: String,
        keyword: String? = nil,
        version: String? = nil,
        length: Int? = nil,
        deprecated: Bool? = nil,
        source: ModelSource = .local
    ) {
        self.name = name
        self.file = file
        self.keyword = keyword
        self.version = version
        self.length = length
        self.deprecated = deprecated
        self.source = source
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(file)
    }

    public static func == (lhs: TextualInversionModel, rhs: TextualInversionModel) -> Bool {
        lhs.file == rhs.file
    }
}

/// Upscaler model information from the server.
public struct UpscalerModel: Identifiable, Codable, Hashable, Sendable {
    public var id: String { file }
    public let name: String
    public let file: String
    public let scaleFactor: Int?
    public let blocks: Int?

    /// The source of this model (local, official, or community).
    public var source: ModelSource

    enum CodingKeys: String, CodingKey {
        case name, file, blocks, source
        case scaleFactor = "scale_factor"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        file = try container.decode(String.self, forKey: .file)
        scaleFactor = try container.decodeIfPresent(Int.self, forKey: .scaleFactor)
        blocks = try container.decodeIfPresent(Int.self, forKey: .blocks)
        source = try container.decodeIfPresent(ModelSource.self, forKey: .source) ?? .local
    }

    public init(
        name: String,
        file: String,
        scaleFactor: Int? = nil,
        blocks: Int? = nil,
        source: ModelSource = .local
    ) {
        self.name = name
        self.file = file
        self.scaleFactor = scaleFactor
        self.blocks = blocks
        self.source = source
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(file)
    }

    public static func == (lhs: UpscalerModel, rhs: UpscalerModel) -> Bool {
        lhs.file == rhs.file
    }
}

// MARK: - Version Normalization

/// Normalizes model version strings to a canonical format.
/// Handles the mapping between camelCase versions (from server) and underscore versions.
///
/// Based on Draw Things ModelZoo version mappings:
/// - SDXL: `sdxlBase`, `sdxlRefiner`, `ssd1b`
/// - SD3: `sd3`, `sd3Large`
/// - Flux: `flux1`
/// - Wan: `wan21_1_3b`, `wan21_14b`, `wan22_5b`
/// - Video: `hunyuanVideo`, `svdI2v`
/// - Cascade: `wurstchenStageC`, `wurstchenStageB`
/// - Other: `kandinsky21`, `pixart`, `auraflow`, `hiDreamI1`, `qwenImage`, `zImage`
public enum ModelVersionNormalizer {
    /// Mapping from camelCase to canonical underscore format.
    private static let versionMap: [String: String] = [
        // SDXL family
        "sdxlBase": "sdxl_base_v0.9",
        "sdxlRefiner": "sdxl_refiner_v0.9",
        "ssd1b": "ssd_1b",
        // Stable Diffusion 3
        "sd3": "sd3",
        "sd3Large": "sd3_large",
        // Kandinsky
        "kandinsky21": "kandinsky2.1",
        // Stable Video Diffusion
        "svdI2v": "svd_i2v",
        // Stable Cascade (Würstchen)
        "wurstchenStageC": "wurstchen_v3.0_stage_c",
        "wurstchenStageB": "wurstchen_v3.0_stage_b",
        // Flux
        "flux1": "flux1",
        // PixArt
        "pixart": "pixart",
        // AuraFlow
        "auraflow": "auraflow",
        // HiDream
        "hiDreamI1": "hidream_i1",
        // Qwen Image
        "qwenImage": "qwen_image",
        // Z Image
        "zImage": "z_image",
        // Hunyuan Video
        "hunyuanVideo": "hunyuan_video",
        // LTX Video
        "ltx2": "ltx_2",
        "ltx2_3": "ltx_2.3",
        // Wan models
        "wan21_1_3b": "wan_v2.1_1.3b",
        "wan21_14b": "wan_v2.1_14b",
        "wan22_5b": "wan_v2.2_5b",
    ]

    /// Reverse mapping from underscore to camelCase format.
    private static let reverseMap: [String: String] = {
        Dictionary(uniqueKeysWithValues: versionMap.map { ($1, $0) })
    }()

    /// Normalizes a version string to the canonical underscore format.
    /// - Parameter version: The version string (either format)
    /// - Returns: The normalized version string
    public static func normalize(_ version: String) -> String {
        // If it's a camelCase version, map it
        if let mapped = versionMap[version] {
            return mapped
        }
        // Already in canonical format or unknown
        return version
    }

    /// Checks if two version strings are compatible (same model family).
    /// - Parameters:
    ///   - version1: First version string
    ///   - version2: Second version string
    /// - Returns: True if the versions are compatible
    public static func areCompatible(_ version1: String?, _ version2: String?) -> Bool {
        guard let v1 = version1, let v2 = version2 else {
            // If either is nil, consider them compatible (show all)
            return true
        }
        return normalize(v1) == normalize(v2)
    }

    /// Returns all version strings that are compatible with the given version.
    /// Useful for filtering when you need to match against multiple formats.
    /// - Parameter version: The version string
    /// - Returns: Set of all compatible version strings (both formats)
    public static func compatibleVersions(for version: String) -> Set<String> {
        let normalized = normalize(version)
        var versions: Set<String> = [version, normalized]

        // Add reverse mapping if it exists
        if let camelCase = reverseMap[normalized] {
            versions.insert(camelCase)
        }

        return versions
    }
}

// MARK: - Models Manager

/// Manages model catalogs received from the Draw Things server.
/// Provides filtering for model compatibility based on version matching.
///
/// Operates in two modes:
/// - Cloud mode (default): Shows cloud models (official + community) for bridge mode users
/// - Local mode: Shows local models received from a connected gRPC server
///
/// Set `useLocalModels` to true to switch to local mode when connected to a server.
@MainActor
@Observable
public final class ModelsManager {
    // MARK: - Local Models (from server)

    public private(set) var localCheckpoints: [CheckpointModel] = []
    public private(set) var localLoRAs: [LoRAModel] = []
    public private(set) var localControlNets: [ControlNetModel] = []
    public private(set) var localTextualInversions: [TextualInversionModel] = []
    public private(set) var localUpscalers: [UpscalerModel] = []

    // MARK: - Mode Settings

    /// Bridge Mode - when true, shows cloud models (official + community).
    /// When false, shows local models from the connected server.
    /// Matches Draw Things terminology where Bridge Mode = cloud generation.
    public var bridgeMode: Bool = true

    // MARK: - Model Lists (Either cloud OR local)

    /// Available checkpoints - when bridgeMode is on, shows cloud + local with deduplication.
    /// When off, shows only local models.
    /// Deduplication priority: Official > Community > Local
    public var checkpoints: [CheckpointModel] {
        if bridgeMode {
            return mergeModels(
                cloud: CloudModels.allCheckpoints,
                local: localCheckpoints,
                getId: { $0.file }
            )
        } else {
            return localCheckpoints
        }
    }

    /// Available LoRAs - when bridgeMode is on, shows cloud + local with deduplication.
    /// When off, shows only local models.
    /// Deduplication priority: Official > Community > Local
    public var loras: [LoRAModel] {
        if bridgeMode {
            return mergeModels(
                cloud: CloudModels.allLoRAs,
                local: localLoRAs,
                getId: { $0.file }
            )
        } else {
            return localLoRAs
        }
    }

    /// Available ControlNets - when bridgeMode is on, shows cloud + local with deduplication.
    /// When off, shows only local models.
    /// Deduplication priority: Official > Community > Local
    public var controlNets: [ControlNetModel] {
        if bridgeMode {
            return mergeModels(
                cloud: CloudModels.allControlNets,
                local: localControlNets,
                getId: { $0.file }
            )
        } else {
            return localControlNets
        }
    }

    /// Available textual inversions - when bridgeMode is on, shows cloud + local with deduplication.
    /// When off, shows only local models.
    public var textualInversions: [TextualInversionModel] {
        if bridgeMode {
            return mergeModels(
                cloud: CloudModels.allTextualInversions,
                local: localTextualInversions,
                getId: { $0.file }
            )
        } else {
            return localTextualInversions
        }
    }

    /// Available upscalers - when bridgeMode is on, shows cloud + local with deduplication.
    /// When off, shows only local models.
    public var upscalers: [UpscalerModel] {
        if bridgeMode {
            return mergeModels(
                cloud: CloudModels.allUpscalers,
                local: localUpscalers,
                getId: { $0.file }
            )
        } else {
            return localUpscalers
        }
    }

    // MARK: - Merging Logic

    /// Merges cloud and local models with deduplication.
    /// Priority: Official > Community > Local
    /// - Parameters:
    ///   - cloud: Cloud models (official + community)
    ///   - local: Local models from connected server
    ///   - getId: Function to extract the unique identifier (filename) from a model
    /// - Returns: Merged list with duplicates resolved by priority
    private func mergeModels<T>(
        cloud: [T],
        local: [T],
        getId: (T) -> String
    ) -> [T] where T: Any {
        // Build a dictionary of cloud models by ID
        // Since cloud models are already sorted by source (official first, then community),
        // we can just use them as-is for the lookup
        var seenIds = Set<String>()
        var result: [T] = []

        // Add cloud models first (they have priority)
        for model in cloud {
            let id = getId(model)
            if !seenIds.contains(id) {
                seenIds.insert(id)
                result.append(model)
            }
        }

        // Add local models that don't overlap with cloud
        for model in local {
            let id = getId(model)
            if !seenIds.contains(id) {
                seenIds.insert(id)
                result.append(model)
            }
        }

        return result
    }

    /// Whether any local models have been received from a server.
    public var hasLocalModels: Bool {
        !localCheckpoints.isEmpty || !localLoRAs.isEmpty || !localControlNets.isEmpty
    }

    public var selectedCheckpoint: CheckpointModel?

    public init() {}

    // MARK: - Compatibility Filtering

    /// LoRAs compatible with the currently selected checkpoint.
    /// Uses version normalization to handle different version string formats.
    public var compatibleLoRAs: [LoRAModel] {
        guard let checkpoint = selectedCheckpoint,
              let checkpointVersion = checkpoint.version else {
            return loras
        }
        return loras.filter { ModelVersionNormalizer.areCompatible($0.version, checkpointVersion) }
    }

    /// ControlNets compatible with the currently selected checkpoint.
    /// Uses version normalization to handle different version string formats.
    public var compatibleControlNets: [ControlNetModel] {
        guard let checkpoint = selectedCheckpoint,
              let checkpointVersion = checkpoint.version else {
            return controlNets
        }
        return controlNets.filter { ModelVersionNormalizer.areCompatible($0.version, checkpointVersion) }
    }

    /// Textual inversions compatible with the currently selected checkpoint.
    /// Uses version normalization to handle different version string formats.
    public var compatibleTextualInversions: [TextualInversionModel] {
        guard let checkpoint = selectedCheckpoint,
              let checkpointVersion = checkpoint.version else {
            return textualInversions
        }
        return textualInversions.filter { ModelVersionNormalizer.areCompatible($0.version, checkpointVersion) }
    }

    /// Checkpoint models that are refiners (version contains "refiner").
    public var refinerModels: [CheckpointModel] {
        checkpoints.filter { $0.version?.contains("refiner") == true }
    }

    /// Checkpoint models that are not refiners.
    public var baseModels: [CheckpointModel] {
        checkpoints.filter { $0.version?.contains("refiner") != true }
    }

    // MARK: - Update from Server

    /// Update model catalogs from server metadata.
    /// - Parameter metadata: The MetadataOverride from the server echo response.
    /// Entries that can't be read (for example without a `name`) are skipped rather than
    /// discarding the whole list.
    public func updateFromMetadata(_ metadata: MetadataOverride) {
        if let models = Self.decodeEach(CheckpointModel.self, from: metadata.models) { localCheckpoints = models }
        if let models = Self.decodeEach(LoRAModel.self, from: metadata.loras) { localLoRAs = models }
        if let models = Self.decodeEach(ControlNetModel.self, from: metadata.controlNets) { localControlNets = models }
        if let models = Self.decodeEach(TextualInversionModel.self, from: metadata.textualInversions) { localTextualInversions = models }
        if let models = Self.decodeEach(UpscalerModel.self, from: metadata.upscalers) { localUpscalers = models }
    }

    /// Decodes a JSON array element by element. Returns nil for empty or non-array data.
    static func decodeEach<Model: Decodable>(_ type: Model.Type, from data: Data) -> [Model]? {
        guard !data.isEmpty, let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return nil }
        let decoder = JSONDecoder()
        var skipped = 0
        let models = array.compactMap { element -> Model? in
            guard let json = try? JSONSerialization.data(withJSONObject: element),
                  let model = try? decoder.decode(Model.self, from: json) else {
                skipped += 1
                return nil
            }
            return model
        }
        if skipped > 0 {
            DTLogger.warning("Skipped \(skipped) unreadable \(Model.self) entries from the server", category: .models)
        }
        return models
    }

    /// Clear local model data (when disconnecting from server or connecting to a different server).
    /// Cloud models remain available.
    public func clearLocalModels() {
        localCheckpoints = []
        localLoRAs = []
        localControlNets = []
        localTextualInversions = []
        localUpscalers = []
        selectedCheckpoint = nil
    }

    /// Check if any models are available (local or cloud).
    public var isEmpty: Bool {
        checkpoints.isEmpty && loras.isEmpty && controlNets.isEmpty
    }

    /// Find a checkpoint model by its filename.
    /// - Parameter filename: The model filename (e.g., "qwen_image_1.0_q8p.ckpt")
    /// - Returns: The matching CheckpointModel, or nil if not found
    public func checkpoint(forFile filename: String) -> CheckpointModel? {
        checkpoints.first { $0.file == filename }
    }

    /// Get the model version string for a given filename.
    /// - Parameter filename: The model filename
    /// - Returns: The version string (e.g., "qwenImage", "flux1"), or nil if not found
    public func version(forFile filename: String) -> String? {
        checkpoint(forFile: filename)?.version
    }

    /// The model family for a file, from the catalog's version when the model is known.
    /// Pass it as `GenerationRequest.modelFamily` for models the file name doesn't identify.
    public func modelFamily(forFile filename: String) -> ModelFamily {
        ModelFamily.detect(from: version(forFile: filename) ?? filename)
    }

    /// Summary of loaded models for display.
    public var summary: String {
        var parts: [String] = []
        if !checkpoints.isEmpty {
            parts.append("\(checkpoints.count) models")
        }
        if !loras.isEmpty {
            parts.append("\(loras.count) LoRAs")
        }
        if !controlNets.isEmpty {
            parts.append("\(controlNets.count) ControlNets")
        }
        return parts.isEmpty ? "No models" : parts.joined(separator: ", ")
    }

    // MARK: - Preview Helpers

    #if DEBUG
    /// Create a ModelsManager with mock checkpoint data for SwiftUI previews.
    public static func preview(withCheckpoints checkpoints: [CheckpointModel]) -> ModelsManager {
        let manager = ModelsManager()
        manager.setLocalCheckpoints(checkpoints)
        return manager
    }

    /// Internal method for setting checkpoints in previews/tests.
    internal func setLocalCheckpoints(_ checkpoints: [CheckpointModel]) {
        self.localCheckpoints = checkpoints
    }
    #endif
}

// MARK: - Preview Helpers

#if DEBUG
extension CheckpointModel {
    /// Create a mock CheckpointModel for previews.
    public static func mock(
        name: String,
        file: String,
        version: String? = nil,
        source: ModelSource = .local
    ) -> CheckpointModel {
        CheckpointModel(
            name: name,
            file: file,
            version: version,
            source: source
        )
    }
}

extension LoRAModel {
    /// Create a mock LoRAModel for previews.
    public static func mock(
        name: String,
        file: String,
        version: String? = nil,
        source: ModelSource = .local
    ) -> LoRAModel {
        LoRAModel(
            name: name,
            file: file,
            version: version,
            source: source
        )
    }
}

extension ControlNetModel {
    /// Create a mock ControlNetModel for previews.
    public static func mock(
        name: String,
        file: String,
        version: String? = nil,
        source: ModelSource = .local
    ) -> ControlNetModel {
        ControlNetModel(
            name: name,
            file: file,
            version: version,
            source: source
        )
    }
}
#endif
