import Foundation
import Testing

@testable import Panorama360F3

@MainActor
struct PluginTests {
  func plugin() -> Panorama360F3Plugin { Panorama360F3Plugin(dataFolder: TestImages.tempFolder()) }

  @Test func theManifestSaysFlux3Only() {
    let manifest = plugin().manifest
    #expect(manifest.id == "com.exiztenz.dthub.panorama360f3" && manifest.name == "Pano 360 F3")
    #expect(manifest.symbol == "globe" && manifest.families == ["flux3_5b"])
    #expect(manifest.version == "1.0")
  }

  @Test func anUnknownMessageIsUnsupportedAndTheKnownOnesAreAnswered() async throws {
    let plugin = plugin()
    let unknown = await plugin.handle(Data(#"{"type":"zzz"}"#.utf8))
    #expect(String(decoding: try #require(unknown), as: UTF8.self).contains("unsupported"))
    for type in ["context", "activate", "deactivate"] {
      #expect(await plugin.handle(Data(#"{"type":"\#(type)","tempFolder":"/tmp"}"#.utf8)) == nil)
    }
  }

  @Test func aSessionNextWithNoRunIsDone() async throws {
    let answer = await plugin().handle(Data(#"{"type":"session.next","index":1,"count":2}"#.utf8))
    #expect(String(decoding: try #require(answer), as: UTF8.self).contains("done"))
  }

  @Test func theMasterPromptIsInstalledInTheDataFolderAtLaunch() {
    let data = TestImages.tempFolder()
    _ = Panorama360F3Plugin(dataFolder: data)
    #expect(FileManager.default.fileExists(atPath: data.appendingPathComponent("panorama-360-f3/master-prompt.md").path))
  }

  @Test func theProjectMessageOpensTheProject() async {
    let plugin = plugin()
    let folder = TestImages.tempFolder()
    _ = await plugin.handle(Data(#"{"type":"project","name":"p","folder":"\#(folder.path)","adoptLegacy":false}"#.utf8))
    #expect(plugin.projectFolderForTests?.path == folder.path)
  }

  @Test func thePresetsAreRegisteredOnce() async {
    let plugin = plugin()
    var calls = 0
    var last: [[String: Any]] = []
    let send: PFPresetSender = { presets in
      calls += 1
      last = presets
      return ["type": "ok"]
    }
    await plugin.registerPresets(using: send)
    await plugin.registerPresets(using: send)
    #expect(calls == 1)
    #expect(last.compactMap { $0["name"] as? String } == ["PANO F3", "PANO F3 Seamfix"])
  }

  @Test func thePresetsAreOfferedAgainWhileTheAppRefuses() async {
    let plugin = plugin()
    var calls = 0
    let refuse: PFPresetSender = { _ in
      calls += 1
      return ["type": "error"]
    }
    await plugin.registerPresets(using: refuse)
    await plugin.registerPresets(using: refuse)
    #expect(calls == 2)
  }
}
