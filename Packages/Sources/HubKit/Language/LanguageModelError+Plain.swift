import Foundation

extension LanguageModelError {
  /// The reason in plain English, for a plug-in to show (the app's own windows use the localized catalog).
  public var plainText: String {
    switch self {
    case .noModelSelected:
      return "No language model is chosen."
    case .notEnoughMemory(let needed, let available):
      return "The language model needs about \(ByteCountFormatter.string(fromByteCount: needed, countStyle: .memory)) "
        + "and only \(ByteCountFormatter.string(fromByteCount: available, countStyle: .memory)) is free."
    case .imagesNotSupported:
      return "The language model cannot read images."
    case .modelNotFound(let name):
      return "The language model “\(name)” is not in the models folder."
    case .interrupted:
      return "The language model was stopped to free the memory for an image."
    case .loadFailed(let detail):
      return "The language model could not be loaded: \(detail)"
    case .generationFailed(let detail):
      return "The language model could not answer: \(detail)"
    case .downloadFailed(let detail):
      return detail
    }
  }
}
