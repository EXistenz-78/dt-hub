import AppKit
import Foundation
import HubCore
import HubKit
import Testing

@testable import PluginHost

@MainActor
final class RecordingHost: PluginHosting {
  private(set) var received: [(message: Data, plugin: String)] = []

  func receive(_ message: Data, from pluginID: String) async -> Data {
    received.append((message, pluginID))
    return PluginMessageType.bare(PluginMessageType.ok)
  }
}

/// Waits, polling, until `condition` holds (10 seconds at most): the plug-in speaks in its own time.
@MainActor
func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
  for _ in 0..<2000 {
    if condition() { return true }
    try? await Task.sleep(for: .milliseconds(5))
  }
  return condition()
}

/// These load a real bundle, built from the sample plug-in of the repository (a `swift build`, some seconds).
@MainActor
struct BundlePluginLoaderTests {
  func info(_ bundle: URL) throws -> PluginBundleInfo { try PluginBundleReader.read(bundle) }

  @Test func theSampleBundleLoadsAndAnswers() async throws {
    let bundle = try #require(SampleBundle.make(), "the sample plug-in could not be built")
    let host = RecordingHost()
    let plugin = try BundlePluginLoader().load(bundle, info: info(bundle), host: host)
    #expect(plugin.manifest.id == "com.example.dthub.sample" && plugin.manifest.name == "Sample")
    #expect(plugin.manifest.symbol == "star" && plugin.manifest.contract == 1)
    #expect(plugin.viewController is NSViewController)
    // The plug-in spoke to the app at start.
    #expect(await eventually { !host.received.isEmpty })
    let notice = try #require(host.received.first)
    #expect(notice.plugin == "com.example.dthub.sample")
    #expect(PluginMessageType.of(notice.message) == PluginMessageType.notice)
    #expect(String(decoding: notice.message, as: UTF8.self).contains("Sample plug-in started"))
    // The app speaks to the plug-in; an unknown type is "unsupported", a known one "ok".
    let context = try JSONEncoder().encode(
      PluginContext(model: "m.ckpt", family: "flux2_9b", parameters: GenerationParameters(), tempFolder: "/tmp"))
    let known = await plugin.send(context)
    #expect(known.flatMap(PluginMessageType.of) == PluginMessageType.ok)
    let unknown = await plugin.send(PluginMessageType.bare("fly"))
    #expect(unknown.flatMap(PluginMessageType.of) == PluginMessageType.unsupported)
  }

  @Test func aBundleWhoseCodeSaysAnotherIdentifierIsRefused() throws {
    let bundle = try #require(SampleBundle.make(id: "com.example.other"))
    #expect(throws: PluginError.manifestMismatch("com.example.dthub.sample")) {
      try BundlePluginLoader().load(bundle, info: info(bundle), host: RecordingHost())
    }
  }

  @Test func aBundleWithoutThePrincipalClassIsRefused() throws {
    let bundle = try #require(SampleBundle.make(principal: "NoSuchEntry"))
    #expect(throws: PluginError.noEntryPoint) {
      try BundlePluginLoader().load(bundle, info: info(bundle), host: RecordingHost())
    }
  }

  @Test func aBundleMadeForAnotherContractIsRefusedBeforeItsCodeLoads() throws {
    let bundle = try #require(SampleBundle.make(contract: 5))
    #expect(throws: PluginError.contractNotSupported(5)) { try info(bundle) }
  }

  @Test func theRegistryInstallsTurnsOnAndLoadsTheSampleAtTheNextLaunch() async throws {
    let source = try #require(SampleBundle.make())
    let root = SampleBundle.work.appendingPathComponent("registry-\(UUID().uuidString)", isDirectory: true)
    let settings = PluginSettingsStore(fileURL: root.appendingPathComponent("plugins.json"))
    func registry() -> PluginRegistry {
      PluginRegistry(
        folder: PluginFolder(root: root.appendingPathComponent("Plug-ins")), settings: settings,
        loader: BundlePluginLoader(), tempFolder: root)
    }
    let first = registry()
    first.start()
    try first.install(first.offer(for: source))
    #expect(first.entries.map(\.state) == [.loadsAtNextLaunch], "installing a new plug-in turns it on")
    let second = registry()
    second.start()
    #expect(second.entries.map(\.state) == [.loaded])
    #expect(second.activeTabs.map(\.title) == ["Sample"])
    #expect(second.viewController(forTab: "plugin.com.example.dthub.sample") is NSViewController)
    #expect(await eventually { second.latestNotice != nil })
    #expect(second.latestNotice?.text == "Sample plug-in started")
    #expect(second.latestNotice?.pluginName == "Sample")
    let skipped = registry()
    skipped.start(skipping: true)
    #expect(skipped.entries.map(\.state) == [.skipped])
  }

  /// The sample sends what a real plug-in would: a `contribute` with fields, a LoRA, a Moodboard picture
  /// whose file exists; a pipeline; and a question for the language model.
  @Test func theSampleContributesThroughTheRealChannel() async throws {
    let bundle = try #require(SampleBundle.make())
    let host = RecordingHost()
    let plugin = try BundlePluginLoader().load(bundle, info: info(bundle), host: host)
    let folder = SampleBundle.work.appendingPathComponent("lent-\(UUID().uuidString)").path
    let context = try JSONEncoder().encode(
      PluginContext(model: "m.ckpt", family: "flux2_9b", parameters: GenerationParameters(), tempFolder: folder))
    _ = await plugin.send(context)

    _ = await plugin.send(Data(#"{"type":"press","button":"plain"}"#.utf8))
    let plain = try #require(host.received.last { PluginMessageType.of($0.message) == PluginMessageType.contribute })
    let contribution = try #require(PluginContribution(message: plain.message))
    #expect(contribution.fields.values[.steps] == .int(4) && contribution.fields.values[.sampler] == .int(16))
    #expect(contribution.fields.values[.prompt] != nil)
    #expect(contribution.loras.first?.file == "flux_2_sun_direction_lora_v1_lora_f16.ckpt" && contribution.loras.first?.weight == 0.6)
    let picture = try #require(contribution.moodboard.first)
    #expect(FileManager.default.fileExists(atPath: picture.path) && picture.path.hasPrefix(folder))

    _ = await plugin.send(Data(#"{"type":"press","button":"pipeline"}"#.utf8))
    let piped = try #require(host.received.last { PluginMessageType.of($0.message) == PluginMessageType.contribute })
    let pipeline = try #require(PluginContribution(message: piped.message)?.pipeline)
    #expect(pipeline.steps.count == 1 && pipeline.steps[0].moodboard?.count == 1 && pipeline.steps[0].useOutputAsStart == false)
    #expect(pipeline.steps[0].preset == "Sample · Match the sun")

    // The presets the pipeline names are offered before the pipeline (and on request).
    _ = await plugin.send(Data(#"{"type":"press","button":"presets"}"#.utf8))
    let offered = try #require(host.received.last { PluginMessageType.of($0.message) == PluginMessageType.presets })
    let list = try #require(PluginPresets(message: offered.message, origin: "x")).presets
    #expect(list.map(\.name) == ["Sample · Overcast", "Sample · Match the sun"])
    #expect(list[1].parameters.loras.first?.weight == 0.6 && list[0].parameters.loras.isEmpty)
    #expect(list[1].prompt.hasPrefix("match light direction"))

    _ = await plugin.send(Data(#"{"type":"press","button":"ask"}"#.utf8))
    #expect(host.received.contains { PluginMessageType.of($0.message) == PluginMessageType.llm })
    #expect(await plugin.send(Data(#"{"type":"press","button":"nothing"}"#.utf8)).flatMap(PluginMessageType.of) == PluginMessageType.unsupported)
  }
}
