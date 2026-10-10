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
  /// Why a vision-language model was loaded without its vision part (nil when it has it, or is a text model).
  private var visionLoadError: String?

  public init() {
    // The two model families register themselves when their modules are linked: touch both so
    // the linker keeps them.
    _ = LLMModelFactory.shared
    _ = VLMModelFactory.shared
  }

  public func load(_ model: LanguageModelDescriptor) async throws {
    await unload()
    let folder = URL(fileURLWithPath: model.path, isDirectory: true)
    do {
      if model.supportsImages {
        // `loadModelContainer` would fall back to the text-only model without a word, and drop every picture: try the
        // vision model on its own, and remember why it failed.
        ProcessorConfigFix.addFlatFileIfNeeded(in: folder)
        do {
          container = try await VLMModelFactory.shared.loadContainer(from: folder, using: TransformersTokenizerLoader())
        } catch {
          visionLoadError = String(String(describing: error).prefix(300))
          container = try await LLMModelFactory.shared.loadContainer(from: folder, using: TransformersTokenizerLoader())
        }
      } else {
        container = try await loadModelContainer(from: folder, using: TransformersTokenizerLoader())
      }
    } catch {
      throw LanguageModelError.loadFailed(error.localizedDescription)
    }
  }

  public func unload() async {
    container = nil
    visionLoadError = nil
    MLX.Memory.clearCache()
  }

  public func respond(
    to prompt: String, images: [URL], options: LanguageModelOptions, history: [LanguageModelTurn]
  ) async throws -> String {
    guard let container else { throw LanguageModelError.loadFailed("No model is loaded.") }
    if let error = Self.visionRequestError(images: images, visionLoadError: visionLoadError) { throw error }
    // A new session per question. A plug-in's chat sends its earlier turns each time, and the session starts from them;
    // a single question has none.
    let session =
      history.isEmpty
      ? ChatSession(
        container, instructions: options.system, generateParameters: Self.generateParameters(for: options),
        additionalContext: Self.templateContext(for: options))
      : ChatSession(
        container, instructions: options.system, history: history.map(Self.message),
        generateParameters: Self.generateParameters(for: options), additionalContext: Self.templateContext(for: options))
    do {
      return try await session.respond(
        to: prompt, role: .user, images: images.map { UserInput.Image.url($0) }, videos: [], audios: [])
    } catch {
      throw LanguageModelError.generationFailed(error.localizedDescription)
    }
  }

  /// A turn of the conversation as the chat session wants it.
  static func message(_ turn: LanguageModelTurn) -> Chat.Message {
    turn.role == .user ? .user(turn.text) : .assistant(turn.text)
  }

  /// A picture for a model that is loaded without its vision part is an error, not a picture quietly dropped.
  static func visionRequestError(images: [URL], visionLoadError: String?) -> LanguageModelError? {
    guard !images.isEmpty, let visionLoadError else { return nil }
    return .loadFailed("The model was loaded without its vision part, so it cannot read pictures: \(visionLoadError)")
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
