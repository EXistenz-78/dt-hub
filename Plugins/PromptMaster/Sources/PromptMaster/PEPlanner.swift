import DTHubPluginKit
import Foundation

/// Why Qwen Image 2.1 still goes to the generic model.
enum PEFallback: Equatable {
  case modelMissing
  case systemPromptMissing(model: String)
}

/// A call to Qwen's prompt enhancer for text-to-image.
struct Enhancer: Equatable {
  /// The name of the model in the app's models folder.
  var model: String
  /// The enhancer's own system prompt, read from its folder.
  var system: String
  var options: DTHubLLMOptions
}

enum PEPlan: Equatable {
  /// The generic language model with the family's master prompt; `reason` says why the enhancer was not used.
  case generic(reason: PEFallback?)
  case enhancer(Enhancer)
}

/// Qwen Image 2.1 has a prompt enhancer of its own (spec §7); this decides whether to use it. Always the text-to-image
/// one: the image-editing enhancer belongs to a plug-in of its own. A pure function of what the app said and what is in
/// the folders.
enum PEPlanner {
  static let family = "qwen_image_2.1"
  static let marker = "qwen_image_2_1_pe_t2i"
  static let systemFileNames = ["system_prompt.txt", "system_prompt_t2i.txt"]

  /// Qwen's recommended settings (the enhancer thinks first, so it may take minutes).
  static let options = DTHubLLMOptions(
    temperature: 1.0, topP: 0.95, topK: 20, presencePenalty: 1.5, maxTokens: 16256, thinking: true, timeout: 900)

  /// `-` and `.` read as `_`, in lower case: `Qwen-Image-2.1-PE-T2I-MLX-4bit` and `qwen3.5_9b_qwen_image_2.1_pe_t2i` both match.
  static func normalized(_ name: String) -> String {
    name.lowercased().map { $0 == "-" || $0 == "." ? "_" : $0 }.reduce(into: "") { $0.append($1) }
  }

  /// Of several folders that match, the biggest wins (the most precise: 8 bit over 4 bit).
  static func plan(
    family: String?, languageModels: [DTHubLanguageModel], folderSize: (String) -> Int64, readFile: (URL) -> String?
  ) -> PEPlan {
    guard family == Self.family else { return .generic(reason: nil) }
    let candidates = languageModels.filter { normalized($0.name).contains(marker) }
    guard let model = candidates.max(by: { folderSize($0.path) < folderSize($1.path) }) else {
      return .generic(reason: .modelMissing)
    }
    let folder = URL(fileURLWithPath: model.path, isDirectory: true)
    let system = systemFileNames
      .compactMap { readFile(folder.appendingPathComponent($0)) }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty }
    guard let system else { return .generic(reason: .systemPromptMissing(model: model.name)) }
    return .enhancer(Enhancer(model: model.name, system: system, options: options))
  }

  /// The size of the files in a folder, for choosing between two enhancers.
  static func folderSize(_ path: String) -> Int64 {
    let urls = (try? FileManager.default.contentsOfDirectory(
      at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.fileSizeKey])) ?? []
    return urls.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
  }
}
