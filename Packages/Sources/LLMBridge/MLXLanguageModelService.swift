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

  public func respond(to prompt: String, images: [URL]) async throws -> String {
    guard let container else { throw LanguageModelError.loadFailed("No model is loaded.") }
    // A new session per question: DT Hub asks single questions, with no conversation to keep.
    let session = ChatSession(container, generateParameters: GenerateParameters(maxTokens: 1024, temperature: 0.6))
    do {
      return try await session.respond(
        to: prompt, role: .user, images: images.map { UserInput.Image.url($0) }, videos: [], audios: [])
    } catch {
      throw LanguageModelError.generationFailed(error.localizedDescription)
    }
  }
}
