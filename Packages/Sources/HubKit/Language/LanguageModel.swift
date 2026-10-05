import Foundation

/// A language model found in the models folder: a folder in Hugging Face format
/// (`config.json` and `.safetensors` weights), the format MLX loads (spec §9).
public struct LanguageModelDescriptor: Identifiable, Equatable, Sendable {
  public var id: String { path }
  /// The folder of the model.
  public let path: String
  /// Its name: the path below the models folder (`mlx-community/Qwen3-VL-8B-Instruct-4bit`, or
  /// just the folder name).
  public let name: String
  /// The size of its files, a good measure of the memory it needs.
  public let sizeBytes: Int64
  /// True for a vision-language model: it can be given images.
  public let supportsImages: Bool

  public init(path: String, name: String, sizeBytes: Int64, supportsImages: Bool) {
    self.path = path
    self.name = name
    self.sizeBytes = sizeBytes
    self.supportsImages = supportsImages
  }
}

/// Why the language model could not do what was asked.
public enum LanguageModelError: Error, Equatable, Sendable {
  case noModelSelected
  /// The model does not fit in the memory that is free now.
  case notEnoughMemory(neededBytes: Int64, availableBytes: Int64)
  case imagesNotSupported
  /// A plug-in asked for a model by name and the models folder has none with that name.
  case modelNotFound(String)
  /// The model was freed while it was loading, because RUN needed the memory.
  case interrupted
  case loadFailed(String)
  case generationFailed(String)
  case downloadFailed(String)
}

/// The language model as HubCore sees it (spec §4: HubCore reaches MLX only through this).
/// LLMBridge implements it with mlx-swift-lm; tests use a fake. One model at a time.
public protocol LanguageModelService: Sendable {
  /// Loads the model into memory, replacing the one loaded.
  func load(_ model: LanguageModelDescriptor) async throws
  /// Frees the memory of the loaded model; does nothing when none is loaded.
  func unload() async
  /// One question, with images for a vision model and the options of `LanguageModelOptions`. The model must be loaded.
  func respond(to prompt: String, images: [URL], options: LanguageModelOptions) async throws -> String
}

extension LanguageModelService {
  /// A question with the default options.
  public func respond(to prompt: String, images: [URL]) async throws -> String {
    try await respond(to: prompt, images: images, options: LanguageModelOptions())
  }
}

/// Downloads a model from Hugging Face into a folder, only when the user asked (spec §9).
public protocol LanguageModelDownloader: Sendable {
  /// `progress` goes from 0 to 1. The files land in `folder` (created when missing).
  func download(
    repository: String, to folder: URL, progress: @escaping @Sendable (Double) -> Void
  ) async throws
}

/// The model DT Hub offers to download (spec §9). The exact repository was checked on
/// Hugging Face on 1 October 2026: 17 files, Apache-2.0.
public enum RecommendedLanguageModel {
  public static let repository = "mlx-community/Qwen3-VL-8B-Instruct-4bit"
  /// Rounded, for the question "download about 5.8 GB?".
  public static let approximateBytes: Int64 = 5_780_000_000
  /// Where it goes inside the models folder: the same layout the scanner reads.
  public static let folderName = repository
}
