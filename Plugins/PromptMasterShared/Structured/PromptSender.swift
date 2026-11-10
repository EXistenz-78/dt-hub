import Foundation

/// The «Send» button apart from the screen: the text goes in the Prompt field and `negative` in the negative prompt (empty
/// unless the plug-in writes one, so nothing of an earlier generation stays). It talks to the app through a closure, so a
/// test can stand in for it.
@MainActor
struct PromptSender {
  /// `host.contribute`.
  var contribute: @MainActor ([String: Any]) async -> [String: Any]?
  var italian = L.systemIsItalian

  struct Outcome: Equatable {
    var status: String
    var sent: Bool
  }

  func send(_ text: String, negative: String = "") async -> Outcome {
    let result = await contribute(["fields": ["prompt": text, "negativePrompt": negative]])
    return Outcome(status: Self.describe(result, italian: italian), sent: Self.wasAccepted(result))
  }

  static func wasAccepted(_ answer: [String: Any]?) -> Bool {
    guard let answer else { return false }
    return answer["type"] as? String != "error"
  }

  static func describe(_ answer: [String: Any]?, italian: Bool) -> String {
    guard let answer else { return L.text(.notAnswered, italian: italian) }
    if answer["type"] as? String == "error" { return answer["text"] as? String ?? L.text(.notAnswered, italian: italian) }
    let conflicts = answer["conflicts"] as? Int ?? 0
    return conflicts > 0 ? L.format(.sentWithConflicts, conflicts, italian: italian) : L.text(.sent, italian: italian)
  }
}
