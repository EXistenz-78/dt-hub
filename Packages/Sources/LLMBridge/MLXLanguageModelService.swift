import Foundation
import HubKit
import MLX
import MLXLLM
import MLXLMCommon
import MLXVLM

/// The language model on MLX (spec §9): loads a model from a folder in Hugging Face format,
/// answers one question at a time, with images for a vision-language model, and gives its
/// memory back on `unload`. The only module that knows MLX (spec §4).
public actor MLXLanguageModelService: LanguageModelService {
  private var container: ModelContainer?

  public init() {
    // The two model families register themselves when their modules are linked: touch both so
    // the linker keeps them.
    _ = LLMModelFactory.shared
    _ = VLMModelFactory.shared
  }

  public func load(_ model: LanguageModelDescriptor) async throws {
    await unload()
    do {
      container = try await loadModelContainer(
        from: URL(fileURLWithPath: model.path, isDirectory: true), using: TransformersTokenizerLoader())
    } catch {
      throw LanguageModelError.loadFailed(error.localizedDescription)
    }
  }

  public func unload() async {
    container = nil
    MLX.Memory.clearCache()
  }

  public func respond(to prompt: String, images: [URL], options: LanguageModelOptions) async throws -> String {
    guard let container else { throw LanguageModelError.loadFailed("No model is loaded.") }
    // A new session per question: DT Hub asks single questions, with no conversation to keep.
    let session = ChatSession(
      container, instructions: options.system, generateParameters: Self.generateParameters(for: options),
      additionalContext: Self.templateContext(for: options))
    do {
      return try await session.respond(
        to: prompt, role: .user, images: images.map { UserInput.Image.url($0) }, videos: [], audios: [])
    } catch {
      throw LanguageModelError.generationFailed(error.localizedDescription)
    }
  }

  /// The defaults are the ones DT Hub always had: temperature 0.6, 1024 tokens.
  static func generateParameters(for options: LanguageModelOptions) -> GenerateParameters {
    GenerateParameters(
      maxTokens: options.maxTokens ?? 1024, temperature: Float(options.temperature ?? 0.6),
      topP: Float(options.topP ?? 1), topK: options.topK ?? 0, presencePenalty: options.presencePenalty.map { Float($0) })
  }

  /// What the chat template is told: `enable_thinking`, only when the plug-in said something.
  static func templateContext(for options: LanguageModelOptions) -> [String: any Sendable]? {
    options.thinking.map { ["enable_thinking": $0] }
  }
}
