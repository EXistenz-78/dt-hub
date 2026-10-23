import Foundation
import Testing

@testable import PromptMasterMOSS

@MainActor
struct PluginTests {
  func plugin() -> MossPlugin {
    MossPlugin(
      dataFolder: FileManager.default.temporaryDirectory.appendingPathComponent("moss-plugin-\(UUID().uuidString)"),
      store: MossStore(storage: MemoryStorage()))
  }

  /// Un tab pronto: attivo, con la dimensione del contesto, una descrizione e un elemento con la caption.
  func ready(_ plugin: MossPlugin) async {
    _ = await plugin.handle(Data(#"{"type":"activate"}"#.utf8))
    _ = await plugin.handle(Data(#"{"type":"context","parameters":{"width":1024,"height":640}}"#.utf8))
    plugin.state.document.description = "A scene."
    plugin.state.addItem(label: .object, box: FracBox(x0: 0.25, y0: 0.25, x1: 0.75, y1: 0.75))
    plugin.state.update(item: 1) { $0.caption = "A cup." }
  }

  @Test func senderPutsTheJSONInThePromptAndTheNegativeInItsField() async {
    final class Box: @unchecked Sendable { var fields: [String: Any] = [:] }
    let box = Box()
    let sender = MossSender(contribute: { payload in box.fields = payload["fields"] as? [String: Any] ?? [:]; return [:] }, italian: false)
    let outcome = await sender.send("JSON", negative: "worst quality, bad anatomy")
    #expect(box.fields["prompt"] as? String == "JSON")
    #expect(box.fields["negativePrompt"] as? String == "worst quality, bad anatomy")
    #expect(outcome.sent && outcome.status == "Prompt sent.")
  }

  @Test func senderReportsConflictsAndErrors() async {
    let withConflicts = await MossSender(contribute: { _ in ["conflicts": 2] }, italian: false).send("x", negative: "")
    #expect(withConflicts.status == "Prompt sent. 2 conflict(s) waiting in the app.")
    let failed = await MossSender(contribute: { _ in ["type": "error", "text": "no"] }, italian: false).send("x", negative: "")
    #expect(!failed.sent && failed.status == "no")
    let silent = await MossSender(contribute: { _ in nil }, italian: false).send("x", negative: "")
    #expect(!silent.sent && silent.status == "The app did not answer.")
  }

  @Test func contextMessagesSetTheGenerationSize_unknownOnesAreUnsupported() async {
    let plugin = plugin()
    let context = await plugin.handle(Data(#"{"type":"context","parameters":{"width":1536,"height":1024}}"#.utf8))
    #expect(context == nil && plugin.state.generationSize == PixelSize(width: 1536, height: 1024))
    #expect(await plugin.handle(Data(#"{"type":"whatever"}"#.utf8)) != nil)
  }

  @Test func theSendPayloadIsTheComposedJSONWithTheNegative() async {
    let plugin = plugin()
    await ready(plugin)
    let payload = plugin.sendPayload()
    let expected = MossComposer.json(plugin.state.document, catalog: plugin.state.catalog, size: PixelSize(width: 1024, height: 640))
    #expect(payload?.json == expected)
    #expect(payload?.negative == "worst quality, bad anatomy")
  }

  @Test func theReviewedTextIsWhatIsSent() async {
    let plugin = plugin()
    await ready(plugin)
    plugin.state.editJSON("{\"edited\":true}")
    #expect(plugin.sendPayload()?.json == "{\"edited\":true}")
  }

  @Test func nothingIsSentWithoutASizeAnElementOrAnActiveTab() async {
    let plugin = plugin()
    #expect(plugin.sendPayload() == nil)  // inattivo
    await ready(plugin)
    _ = await plugin.handle(Data(#"{"type":"context","parameters":{"width":1000,"height":640}}"#.utf8))  // non multiplo di 16
    #expect(plugin.sendPayload() == nil)
    _ = await plugin.handle(Data(#"{"type":"context","parameters":{"width":1024,"height":640}}"#.utf8))
    #expect(plugin.sendPayload() != nil)
    plugin.state.removeItem(1)
    #expect(plugin.sendPayload() == nil)
    _ = await plugin.handle(Data(#"{"type":"deactivate"}"#.utf8))
    #expect(!plugin.state.active)
  }

  @Test func aProjectMessageMovesTheSessionToThatProjectsFolder() async throws {
    let plugin = plugin()
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("moss-proj-\(UUID().uuidString)")
    let answer = await plugin.handle(Data(#"{"type":"project","name":"Test","folder":"\#(folder.path)","adoptLegacy":false}"#.utf8))
    #expect(answer == nil)
    #expect(plugin.state.projectFolder?.path == folder.path)
  }

  @Test func theTableIsCompleteInBothLanguages() {
    for key in L.Key.allCases {
      #expect(L.isDefined(key, italian: true), "it \(key)")
      #expect(L.isDefined(key, italian: false), "en \(key)")
    }
  }
}
