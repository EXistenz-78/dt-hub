import Foundation

/// The text of the panorama pass. The LoRA's trigger word is never written here: DT Hub puts it in front of the prompt.
enum PFPrompt {
  /// `starting from <image 1>, <image 2>, …` for `count` pictures; empty for none.
  static func references(count: Int) -> String {
    guard count > 0 else { return "" }
    return "starting from " + (1...count).map { "<image \($0)>" }.joined(separator: ", ")
  }

  /// The references, then (only when the description is not blank) a dot, a space and the description.
  static func panorama(imageCount: Int, description: String) -> String {
    let references = references(count: imageCount)
    guard !references.isEmpty else { return "" }
    let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? references : references + ". " + text
  }
}
