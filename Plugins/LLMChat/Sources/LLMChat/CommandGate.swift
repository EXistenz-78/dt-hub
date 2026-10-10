import Foundation

/// The command that lets the LLM act on the app. Only `<FALLO>` and `<DO IT>`, exactly so (capitals and angle brackets),
/// anywhere in the user's message and whatever the language of the app.
enum CommandGate {
  static let commands = ["<FALLO>", "<DO IT>"]

  static func isOpen(_ userText: String) -> Bool {
    commands.contains { userText.contains($0) }
  }
}
