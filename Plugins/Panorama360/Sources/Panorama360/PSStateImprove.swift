import DTHubPluginKit
import Foundation

extension PSState {
  /// Rewrites the description with the language model (`ask(prompt, system)` is the app's answer): only the description changes, and
  /// «Undo» brings back the one before. An Italian answer is asked again once; an answer that holds a piece of the trigger phrase is refused.
  func improve(using ask: @MainActor (String, String) async -> DTHubLLMAnswer) async {
    let original = doc.description
    guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      error = text(.emptyDescription)
      return
    }
    error = nil
    isImproving = true
    defer { isImproving = false }
    var request = PSPrompt.request(description: original)
    var answer = await ask(request.prompt, request.system)
    if case .text(let first) = answer, PSPrompt.looksItalian(PSPrompt.clean(first)) {
      request = PSPrompt.request(description: original, reminder: true)
      answer = await ask(request.prompt, request.system)
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

  /// Puts back the description from before the last «Improve prompt» (once).
  func undoImprove() {
    guard let previous = previousDescription else { return }
    previousDescription = nil
    mutate { $0.description = previous }
  }
}
