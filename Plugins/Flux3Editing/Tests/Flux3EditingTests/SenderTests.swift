import Foundation
import Testing

@testable import Flux3Editing

@MainActor
struct SenderTests {
  @Test func sendWritesThePromptAndClearsTheNegative() async {
    var received: [String: Any] = [:]
    let sender = EditSender(contribute: { received = $0; return ["type": "ok"] }, italian: false)
    let outcome = await sender.send("the text")
    let fields = received["fields"] as? [String: Any]
    #expect(fields?["prompt"] as? String == "the text" && fields?["negativePrompt"] as? String == "")
    #expect(outcome.sent && outcome.status == L.text(.sent, italian: false))
  }

  @Test func conflictsAreReported() async {
    let sender = EditSender(contribute: { _ in ["type": "ok", "conflicts": 2] }, italian: false)
    #expect(await sender.send("x").status == L.format(.sentWithConflicts, 2, italian: false))
  }

  @Test func anErrorAnswerIsShownAndNotSent() async {
    let sender = EditSender(contribute: { _ in ["type": "error", "text": "Not the active tab."] }, italian: false)
    let outcome = await sender.send("x")
    #expect(!outcome.sent && outcome.status == "Not the active tab.")
  }

  @Test func noAnswerSaysSo() async {
    let sender = EditSender(contribute: { _ in nil }, italian: false)
    let outcome = await sender.send("x")
    #expect(!outcome.sent && outcome.status == L.text(.notAnswered, italian: false))
  }
}
