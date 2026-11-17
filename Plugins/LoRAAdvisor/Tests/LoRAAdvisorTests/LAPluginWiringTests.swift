import DTHubPluginKit
import Foundation
import Testing

@testable import LoRAAdvisor

/// The plug-in joins the jobs and the state to the app: a job that is not wired would analyse and save nothing.
@MainActor
struct LAPluginWiringTests {
  final class Sent: @unchecked Sendable {
    var settings: [(String, DTHubLoRASettings)] = []
    var weights: [(String, Double?, Double?, Double?)] = []
    var answer: [String: Any]? = ["type": "ok"]
  }

  let store = LAStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent("la-wiring-\(UUID().uuidString)", isDirectory: true))
  let fetcher = FakeFetcher()
  let plugin: LoRAAdvisorPlugin
  let sent = Sent()

  init() {
    let json = #"{"summary":"Stile acquarello.","category":"turbo","weight":{"min":0.6,"base":0.8,"max":1},"turbo":{"steps":8,"guidance":1.5,"shift":3},"triggers":["zap"]}"#
    plugin = LoRAAdvisorPlugin(store: store, fetcher: fetcher, summarise: { _, _ in json }, pause: .zero)
    let sent = sent
    plugin.sendSettings = { file, settings in
      sent.settings.append((file, settings))
      return sent.answer
    }
    plugin.sendWeights = { file, low, base, high in
      sent.weights.append((file, low, base, high))
      return sent.answer
    }
    fetcher.set(
      LACivitai.modelURL(1), text: #"{"description":"<p>Page of Alpha</p>","modelVersions":[{"id":1,"images":[]}]}"#)
    store.update("a.ckpt") { $0.link = "https://civitai.com/models/1" }
    store.setNotesByUser("mie note", for: "a.ckpt")
  }

  func send(context: String) async {
    _ = await plugin.handle(Data(context.utf8))
  }

  let context = #"{"type":"context","tempFolder":"/tmp/x","model":"m","prompt":"p","loraSettings":true,"loraCatalog":[{"file":"a.ckpt","name":"Alpha","family":"b","trigger":"aa","weight":1}]}"#

  @Test func theAnalysisJobSavesThroughThePlugin() async {
    await send(context: context)
    await plugin.state.jobs.summariseAll(plugin.state.catalog)
    #expect(sent.settings.count == 1 && sent.settings[0].0 == "a.ckpt")
    #expect(sent.settings[0].1 == DTHubLoRASettings(category: .set("turbo"), steps: .set(8), guidance: .set(1.5), shift: .set(3)))
    #expect(sent.weights.count == 1 && sent.weights[0].2 == 0.8)
    #expect(store.entry(for: "a.ckpt").analysed)
  }

  @Test func anAnswerThatIsNotOKIsNotASave() async {
    sent.answer = ["type": "error", "text": "no"]
    await send(context: context)
    await plugin.state.jobs.summariseAll(plugin.state.catalog)
    #expect(sent.settings.count == 1 && !store.entry(for: "a.ckpt").analysed)
    sent.answer = nil
    await plugin.state.jobs.summariseAll(plugin.state.catalog)
    #expect(!store.entry(for: "a.ckpt").analysed)
  }

  @Test func theStateSavesThroughThePlugin() async {
    await send(context: context)
    await plugin.state.setCategory(.style, for: "a.ckpt")
    await plugin.state.setWeights(min: 0.5, base: nil, max: nil, for: "a.ckpt")
    #expect(sent.settings.map(\.0) == ["a.ckpt"] && sent.settings[0].1 == DTHubLoRASettings(category: .set("style")))
    #expect(sent.weights.count == 1 && sent.weights[0].1 == 0.5)
  }

  @Test func anAppThatDoesNotKnowTheMessageIsNotASave() async {
    sent.answer = ["type": "unsupported"]
    await send(context: context)
    await plugin.state.jobs.summariseAll(plugin.state.catalog)
    #expect(!store.entry(for: "a.ckpt").analysed)
  }

  @Test func withoutLoRASettingsInTheContextTheJobSavesNothing() async {
    await send(context: context.replacingOccurrences(of: #""loraSettings":true,"#, with: ""))
    await plugin.state.jobs.summariseAll(plugin.state.catalog)
    #expect(sent.settings.isEmpty && !store.entry(for: "a.ckpt").analysed)
  }

  /// The user's edit is still waiting for the app when an analysis runs: the analysis leaves the category alone.
  @Test func anEditInFlightIsNotOverwrittenByTheAnalysis() async {
    await send(context: context)
    let plugin = plugin
    let sent = sent
    var inner = false
    plugin.sendSettings = { file, settings in
      sent.settings.append((file, settings))
      if !inner {
        inner = true
        await plugin.state.jobs.summariseAll(plugin.state.catalog)
      }
      return ["type": "ok"]
    }
    await plugin.state.setCategory(.style, for: "a.ckpt")
    #expect(sent.settings.map(\.1) == [DTHubLoRASettings(category: .set("style"))])
    #expect(store.entry(for: "a.ckpt").categoryManual)
    // A refused edit gives the flag back.
    plugin.sendSettings = { _, _ in nil }
    await plugin.state.setCategory(.slider, for: "p.ckpt")
    #expect(!store.entry(for: "p.ckpt").categoryManual)
  }
}
