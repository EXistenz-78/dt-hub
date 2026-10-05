import DTHubPluginKit
import Foundation

/// Why a family that has prompt enhancers still goes to the generic model.
enum PEFallback: Equatable {
  case modelMissing(PEKind)
  case systemPromptMissing(model: String)
}

enum PEKind: Equatable { case t2i, i2i }

/// A call to a Qwen prompt enhancer.
struct Enhancer: Equatable {
  var kind: PEKind
  /// The name of the model in the app's models folder.
  var model: String
  /// The enhancer's own system prompt, read from its folder.
  var system: String
  /// The pictures it reads: the start image, then the Moodboard (I2I only).
  var images: [String]
  var options: DTHubLLMOptions
}

enum PEPlan: Equatable {
  /// The generic language model with the family's master prompt; `reason` says why a prompt enhancer was not used.
  case generic(reason: PEFallback?)
  case enhancer(Enhancer)
}

/// Qwen Image 2.1 has two prompt enhancers of its own (spec §7); this decides whether and which to use. A pure function
/// of what the app said and what is in the folders, so the rule can be tested and changed in one place.
enum PEPlanner {
  static let family = "qwen_image_2.1"
  static let maxImages = 10
  static let t2iMarker = "qwen_image_2_1_pe_t2i"
  static let i2iMarker = "qwen_image_2_1_pe_i2i"
  static let systemFileNames: [PEKind: [String]] = [
    .t2i: ["system_prompt_t2i.txt", "system_prompt.txt"],
    .i2i: ["system_prompt_edit.txt", "system_prompt_i2i.txt", "system_prompt.txt"],
  ]

  /// Qwen's recommended settings (the enhancer thinks first, so it may take minutes).
  static func options(for kind: PEKind) -> DTHubLLMOptions {
    switch kind {
    case .t2i:
      return DTHubLLMOptions(
        temperature: 1.0, topP: 0.95, topK: 20, presencePenalty: 1.5, maxTokens: 16256, thinking: true, timeout: 900)
    case .i2i:
      return DTHubLLMOptions(
        temperature: 1.0, topP: 0.95, topK: 20, presencePenalty: 0, maxTokens: 24000, thinking: true, timeout: 1200)
    }
  }

  /// `-` and `.` read as `_`, in lower case: `Qwen-Image-2.1-PE-T2I-MLX-4bit` and `qwen3.5_9b_qwen_image_2.1_pe_t2i` both match.
  static func normalized(_ name: String) -> String {
    name.lowercased().map { $0 == "-" || $0 == "." ? "_" : $0 }.reduce(into: "") { $0.append($1) }
  }

  /// - The I2I enhancer is chosen when there is a start image; the Moodboard alone does not make it I2I.
  /// - Of several folders that match, the biggest wins (the most precise: 8 bit over 4 bit).
  static func plan(
    family: String?, startImage: String?, moodboard: [String], languageModels: [DTHubLanguageModel],
    folderSize: (String) -> Int64, readFile: (URL) -> String?
  ) -> PEPlan {
    guard family == Self.family else { return .generic(reason: nil) }
    let kind: PEKind = startImage == nil ? .t2i : .i2i
    let marker = kind == .t2i ? t2iMarker : i2iMarker
    let candidates = languageModels.filter {
      normalized($0.name).contains(marker) && (kind == .t2i || $0.supportsImages)
    }
    guard let model = candidates.max(by: { folderSize($0.path) < folderSize($1.path) }) else {
      return .generic(reason: .modelMissing(kind))
    }
    let folder = URL(fileURLWithPath: model.path, isDirectory: true)
    let system = (systemFileNames[kind] ?? [])
      .compactMap { readFile(folder.appendingPathComponent($0)) }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty }
    guard let system else { return .generic(reason: .systemPromptMissing(model: model.name)) }
    let images = kind == .i2i ? Array(([startImage].compactMap { $0 } + moodboard).prefix(maxImages)) : []
    return .enhancer(Enhancer(kind: kind, model: model.name, system: system, images: images, options: options(for: kind)))
  }

  /// The size of the files in a folder, for choosing between two enhancers.
  static func folderSize(_ path: String) -> Int64 {
    let urls = (try? FileManager.default.contentsOfDirectory(
      at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.fileSizeKey])) ?? []
    return urls.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
  }
}
