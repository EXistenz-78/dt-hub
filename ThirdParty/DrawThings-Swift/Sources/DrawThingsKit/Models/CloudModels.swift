//
//  CloudModels.swift
//  DrawThingsKit
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import Foundation
import DrawThingsClient

/// Container for cloud model lists loaded from bundled JSON files.
private struct CloudModelCatalog: Codable {
    let checkpoints: [CheckpointModel]
    let loras: [LoRAModel]
    let controlNets: [ControlNetModel]
    let textualInversions: [TextualInversionModel]
    let upscalers: [UpscalerModel]

    static let empty = CloudModelCatalog(
        checkpoints: [],
        loras: [],
        controlNets: [],
        textualInversions: [],
        upscalers: []
    )
}

/// Provides access to cloud-available models for Bridge Mode support.
///
/// Models are organized into two categories:
/// - **Official**: Built-in models from Draw Things ModelZoo (available on Community and DrawThings+ plans)
/// - **Community**: User-contributed models from the community-models repository
///
/// Usage:
/// ```swift
/// // Get all official checkpoints
/// let officialModels = CloudModels.officialCheckpoints
///
/// // Get all community LoRAs
/// let communityLoRAs = CloudModels.communityLoRAs
///
/// // Get combined lists
/// let allCheckpoints = CloudModels.allCheckpoints
/// ```
public enum CloudModels {
    // MARK: - Official Models

    /// Official checkpoint models available through Draw Things cloud.
    public static var officialCheckpoints: [CheckpointModel] {
        officialCatalog.checkpoints
    }

    /// Official LoRA models available through Draw Things cloud.
    public static var officialLoRAs: [LoRAModel] {
        officialCatalog.loras
    }

    /// Official ControlNet models available through Draw Things cloud.
    public static var officialControlNets: [ControlNetModel] {
        officialCatalog.controlNets
    }

    /// Official textual inversions available through Draw Things cloud.
    public static var officialTextualInversions: [TextualInversionModel] {
        officialCatalog.textualInversions
    }

    /// Official upscaler models available through Draw Things cloud.
    public static var officialUpscalers: [UpscalerModel] {
        officialCatalog.upscalers
    }

    // MARK: - Community Models

    /// Community checkpoint models available through Draw Things cloud.
    public static var communityCheckpoints: [CheckpointModel] {
        communityCatalog.checkpoints
    }

    /// Community LoRA models available through Draw Things cloud.
    public static var communityLoRAs: [LoRAModel] {
        communityCatalog.loras
    }

    /// Community ControlNet models available through Draw Things cloud.
    public static var communityControlNets: [ControlNetModel] {
        communityCatalog.controlNets
    }

    /// Community textual inversions available through Draw Things cloud.
    public static var communityTextualInversions: [TextualInversionModel] {
        communityCatalog.textualInversions
    }

    /// Community upscaler models available through Draw Things cloud.
    public static var communityUpscalers: [UpscalerModel] {
        communityCatalog.upscalers
    }

    // MARK: - Combined Lists

    /// All cloud checkpoints (official + community).
    public static var allCheckpoints: [CheckpointModel] {
        officialCheckpoints + communityCheckpoints
    }

    /// All cloud LoRAs (official + community).
    public static var allLoRAs: [LoRAModel] {
        officialLoRAs + communityLoRAs
    }

    /// All cloud ControlNets (official + community).
    public static var allControlNets: [ControlNetModel] {
        officialControlNets + communityControlNets
    }

    /// All cloud textual inversions (official + community).
    public static var allTextualInversions: [TextualInversionModel] {
        officialTextualInversions + communityTextualInversions
    }

    /// All cloud upscalers (official + community).
    public static var allUpscalers: [UpscalerModel] {
        officialUpscalers + communityUpscalers
    }

    // MARK: - Private Loading

    private static let officialCatalog: CloudModelCatalog = loadCatalog(
        named: "official_models",
        source: .official
    )

    private static let communityCatalog: CloudModelCatalog = loadCatalog(
        named: "community_models",
        source: .community
    )

    private static func loadCatalog(named name: String, source: ModelSource) -> CloudModelCatalog {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            DTLogger.warning("Could not find \(name).json in bundle", category: .models)
            return .empty
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            var catalog = try decoder.decode(CloudModelCatalog.self, from: data)

            // Set the source on all models
            catalog = CloudModelCatalog(
                checkpoints: catalog.checkpoints.map { var m = $0; m.source = source; return m },
                loras: catalog.loras.map { var m = $0; m.source = source; return m },
                controlNets: catalog.controlNets.map { var m = $0; m.source = source; return m },
                textualInversions: catalog.textualInversions.map { var m = $0; m.source = source; return m },
                upscalers: catalog.upscalers.map { var m = $0; m.source = source; return m }
            )

            return catalog
        } catch {
            DTLogger.error("Failed to load \(name).json: \(error)", category: .models)
            return .empty
        }
    }
}
