import Foundation
import Testing

@testable import PromptMasterF3

@MainActor
struct PluginTests {
  @Test func senderPutsTheTextInThePromptAndEmptiesTheNegative() async {
    final class Box: @unchecked Sendable { var fields: [String: Any] = [:] }
    let box = Box()
    let sender = F3Sender(contribute: { payload in box.fields = payload["fields"] as? [String: Any] ?? [:]; return [:] }, italian: false)
    let outcome = await sender.send("TEXT")
    #expect(box.fields["prompt"] as? String == "TEXT")
    #expect(box.fields["negativePrompt"] as? String == "")
    #expect(outcome.sent)
    #expect(outcome.status == "Prompt sent.")
  }

  @Test func senderReportsConflictsAndErrors() async {
    let withConflicts = await F3Sender(contribute: { _ in ["conflicts": 2] }, italian: false).send("x")
    #expect(withConflicts.status == "Prompt sent. 2 conflict(s) waiting in the app.")
    let failed = await F3Sender(contribute: { _ in ["type": "error", "text": "no"] }, italian: false).send("x")
    #expect(!failed.sent && failed.status == "no")
    let silent = await F3Sender(contribute: { _ in nil }, italian: false).send("x")
    #expect(!silent.sent && silent.status == "The app did not answer.")
  }

  @Test func unknownMessagesAreUnsupported() async {
    let plugin = F3Plugin()
    let answer = await plugin.handle(Data(#"{"type":"whatever"}"#.utf8))
    #expect(answer != nil)
    let context = await plugin.handle(Data(#"{"type":"context","parameters":{"width":1536,"height":1024}}"#.utf8))
    #expect(context == nil)
  }

  @Test func theTableIsCompleteInBothLanguages() {
    for key in L.Key.allCases {
      #expect(L.isDefined(key, italian: true), "it \(key)")
      #expect(L.isDefined(key, italian: false), "en \(key)")
    }
  }
}
