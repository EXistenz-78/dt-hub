import DTHubPluginKit
import Foundation

/// Which earlier messages go to the LLM with a new one.
enum HistoryWindow {
  static let budget = 24_000

  /// The user's and the LLM's messages (the plug-in's notes are left out), the most recent ones that fit in `budget`
  /// characters, never cutting a message, oldest first. `trimmed` says something stayed out. The new message always goes
  /// (it is not in `messages`: it is the prompt of the question).
  static func turns(of messages: [ChatMessage], budget: Int = HistoryWindow.budget) -> (turns: [DTHubLLMTurn], trimmed: Bool) {
    let spoken = messages.filter { $0.role != .note }
    var kept: [DTHubLLMTurn] = []
    var used = 0
    var trimmed = false
    for message in spoken.reversed() {
      if used + message.text.count > budget {
        trimmed = true
        break
      }
      used += message.text.count
      kept.append(DTHubLLMTurn(role: message.role == .user ? .user : .assistant, text: message.text))
    }
    return (kept.reversed(), trimmed)
  }
}
