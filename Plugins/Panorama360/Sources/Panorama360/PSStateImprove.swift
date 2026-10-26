import DTHubPluginKit
import Foundation

extension PSState {
  /// Rewrites the description with the language model (`ask(prompt, system)` is the app's answer): only the description changes, and
  /// «Undo» brings back the one before. An Italian answer is asked again once; an answer that holds a piece of the trigger phrase is refused.
  func improve(using ask: @MainActor (String, String, [String]) async -> DTHubLLMAnswer) async {
    let original = doc.description
    guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      error = text(.emptyDescription)
      return
    }
    error = nil
    let folder = projectFolder
    isImproving = true
    defer { isImproving = false }
    // The canvas goes along as a small picture, when there is something on it.
    let picture = improvePicture()
    defer { if let picture { try? FileManager.default.removeItem(atPath: picture) } }
    let images = picture.map { [$0] } ?? []
    var request = PSPrompt.request(description: original, withPicture: picture != nil)
    var answer = await ask(request.prompt, request.system, images)
    if case .text(let first) = answer, PSPrompt.looksItalian(PSPrompt.clean(first)) {
      request = PSPrompt.request(description: original, reminder: true, withPicture: picture != nil)
      answer = await ask(request.prompt, request.system, images)
    }
    // The answer comes after a wait: if the project or the text changed meanwhile it no longer fits and is dropped.
    guard projectFolder == folder, doc.description == original else {
      error = text(.improveStale)
      return
    }
    switch answer {
    case .failure(let reason):
      error = reason
    case .text(let raw):
      let improved = PSPrompt.clean(raw)
      if improved.isEmpty || PSPrompt.containsTrigger(improved) {
        error = text(.answerRejected)
      } else if PSPrompt.looksItalian(improved) {
        error = text(.answerNotEnglish)
      } else {
        previousDescription = original
        mutate { $0.description = improved }
      }
    }
  }

  /// The ERP canvas as a small PNG in the exchange folder, for the language model; nil when nothing is visible or it cannot be written.
  private func improvePicture() -> String? {
    guard doc.stickers.contains(where: \.visible), let image = try? renderedERP(width: 1024, height: 512) else { return nil }
    let folder = URL(fileURLWithPath: tempFolder.isEmpty ? NSTemporaryDirectory() : tempFolder, isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("panorama-360-improve-\(UUID().uuidString).png")
    return PSSender.writePNG(image, to: file) ? file.path : nil
  }

  /// Puts back the description from before the last «Improve prompt» (once).
  func undoImprove() {
    guard let previous = previousDescription else { return }
    previousDescription = nil
    mutate { $0.description = previous }
  }
}
