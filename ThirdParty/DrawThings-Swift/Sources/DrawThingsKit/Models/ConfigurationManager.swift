//
//  ConfigurationManager.swift
//  DrawThingsKit
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import CoreGraphics
import DrawThingsClient
import Foundation
import Observation

/// Manages the single active configuration used for generation.
///
/// Provides:
/// - Active configuration state
/// - Prompt and model selection state
/// - Draw Things JSON import and export (for copy and paste, pass the JSON to and from the
///   system pasteboard)
///
/// Example usage:
/// ```swift
/// @State private var configurationManager = ConfigurationManager()
///
/// let request = configurationManager.makeRequest()
/// queue.enqueue(request)
/// ```
@MainActor
@Observable
public final class ConfigurationManager {
    /// The active configuration for generation
    public var activeConfiguration: DrawThingsConfiguration = DrawThingsConfiguration()

    /// The active prompt (stored separately as it's not part of DrawThingsConfiguration)
    public var prompt: String = ""

    /// The active negative prompt
    public var negativePrompt: String = ""

    /// Selected checkpoint model (syncs with activeConfiguration.model)
    public var selectedCheckpoint: CheckpointModel? = nil

    /// Selected refiner model (syncs with activeConfiguration.refinerModel)
    public var selectedRefiner: CheckpointModel? = nil

    /// Selected LoRA configurations
    public var selectedLoRAs: [LoRAConfiguration] = []

    /// Selected ControlNet configurations
    public var selectedControls: [ControlNetConfiguration] = []

    /// Mixture of Experts mode - automatically enabled for Wan 2.2 models
    /// When enabled, any model can be used as refiner and LoRAs use MOE-style weights
    public var mixtureOfExperts: Bool {
        guard let checkpoint = selectedCheckpoint else {
            // Fall back to checking the model filename string
            return isWan22ModelName(activeConfiguration.model)
        }
        return isWan22Model(checkpoint)
    }

    /// Check if a checkpoint model is a Wan 2.2 model
    private func isWan22Model(_ model: CheckpointModel) -> Bool {
        // Check version string
        if let version = model.version {
            if version.lowercased().contains("wan22") || version.lowercased().contains("wan_2.2") {
                return true
            }
        }
        // Check file name
        if isWan22ModelName(model.file) {
            return true
        }
        // Check display name
        if model.name.lowercased().contains("wan 2.2") || model.name.lowercased().contains("wan2.2") {
            return true
        }
        return false
    }

    /// Check if a model filename indicates Wan 2.2
    private func isWan22ModelName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("wan_v2.2") || lower.contains("wan_2.2") || lower.contains("wan22")
    }

    public init() {}

    /// Sync model selections to configuration (call before using activeConfiguration)
    public func syncModelsToConfiguration() {
        // Only override model if a checkpoint is selected from the picker
        if let checkpoint = selectedCheckpoint {
            activeConfiguration.model = checkpoint.file
        }
        // Only override refiner if a refiner is selected from the picker
        if let refiner = selectedRefiner {
            activeConfiguration.refinerModel = refiner.file
        }
        // If selectedRefiner is nil but was explicitly cleared (not just unset),
        // we leave activeConfiguration.refinerModel as-is to preserve text field values

        // Sync LoRAs - convert UI configurations to DrawThingsClient format
        activeConfiguration.loras = selectedLoRAs.toLoRAConfigs()

        // Sync ControlNets - convert UI configurations to DrawThingsClient format
        activeConfiguration.controls = selectedControls.toControlConfigs()
    }

    /// Update selected models from a ModelsManager after loading a preset
    /// Call this after loading a configuration to resolve model filenames to CheckpointModel objects
    public func resolveModels(from modelsManager: ModelsManager) {
        // Resolve checkpoint
        selectedCheckpoint = modelsManager.checkpoints.first { $0.file == activeConfiguration.model }

        // Resolve refiner
        if let refinerFile = activeConfiguration.refinerModel {
            selectedRefiner = modelsManager.checkpoints.first { $0.file == refinerFile }
        } else {
            selectedRefiner = nil
        }

        // Resolve LoRAs from configuration
        selectedLoRAs = activeConfiguration.loras.compactMap { loraConfig in
            guard let loraModel = modelsManager.loras.first(where: { $0.file == loraConfig.file }) else {
                return nil
            }
            return LoRAConfiguration(
                lora: loraModel,
                weight: Double(loraConfig.weight),
                mode: loraConfig.mode,
                enabled: true
            )
        }

        // Resolve ControlNets from configuration
        selectedControls = activeConfiguration.controls.compactMap { controlConfig in
            guard let controlModel = modelsManager.controlNets.first(where: { $0.file == controlConfig.file }) else {
                return nil
            }
            return ControlNetConfiguration(
                controlNet: controlModel,
                weight: Double(controlConfig.weight),
                guidanceStart: Double(controlConfig.guidanceStart),
                guidanceEnd: Double(controlConfig.guidanceEnd),
                controlMode: controlConfig.controlMode,
                enabled: true
            )
        }
    }

    // MARK: - Requests

    /// A generation request from the current prompt, models and configuration.
    /// - Parameters:
    ///   - image: Input image for image-to-image and inpainting.
    ///   - mask: Inpainting mask.
    ///   - hints: Control hints, built with `HintBuilder`.
    public func makeRequest(image: CGImage? = nil, mask: CGImage? = nil, hints: [HintProto] = []) -> GenerationRequest {
        syncModelsToConfiguration()
        return GenerationRequest(
            prompt: prompt,
            negativePrompt: negativePrompt,
            configuration: activeConfiguration,
            image: image,
            mask: mask,
            hints: hints,
            modelFamily: selectedCheckpoint?.family
        )
    }

    // MARK: - JSON

    /// Loads Draw Things JSON, such as the app's "Copy Configuration" output. Only fields present
    /// in the JSON change; call ``resolveModels(from:)`` afterwards to update the selections.
    @discardableResult
    public func loadFromJSON(_ json: String) -> Bool {
        do {
            try activeConfiguration.mergeJSON(json)
            return true
        } catch {
            DTLogger.error("Failed to load configuration: \(error)", category: .configuration)
            return false
        }
    }

    /// The current configuration as Draw Things JSON, which pastes into the app.
    public func exportToJSON() -> String? {
        syncModelsToConfiguration()
        return try? activeConfiguration.toJSON()
    }

    /// Reset to default configuration
    public func resetToDefaults() {
        activeConfiguration = DrawThingsConfiguration()
        prompt = ""
        negativePrompt = ""
        selectedCheckpoint = nil
        selectedRefiner = nil
        selectedLoRAs = []
        selectedControls = []
    }
}
