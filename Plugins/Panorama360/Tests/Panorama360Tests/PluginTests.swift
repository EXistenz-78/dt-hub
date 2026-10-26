import Foundation
import Testing

@testable import Panorama360

@MainActor
struct PluginTests {
  func plugin() -> Panorama360Plugin { Panorama360Plugin(dataFolder: TestImages.tempFolder()) }

  @Test func theManifestKeepsItsIdentity() {
    let manifest = plugin().manifest
    #expect(manifest.id == "com.exiztenz.dthub.panorama360" && manifest.name == "Panorama 360")
    #expect(manifest.symbol == "globe" && manifest.families == ["flux2_9b", "flux2_4b"])
  }

  @Test func anUnknownMessageIsUnsupportedAndTheKnownOnesAreAnswered() async throws {
    let plugin = plugin()
    let unknown = await plugin.handle(Data(#"{"type":"zzz"}"#.utf8))
    #expect(String(decoding: try #require(unknown), as: UTF8.self).contains("unsupported"))
    for type in ["context", "activate", "deactivate"] {
      #expect(await plugin.handle(Data(#"{"type":"\#(type)","tempFolder":"/tmp"}"#.utf8)) == nil)
    }
  }

  @Test func theMasterPromptIsInstalledInTheDataFolderAtLaunch() {
    let data = TestImages.tempFolder()
    _ = Panorama360Plugin(dataFolder: data)
    #expect(FileManager.default.fileExists(atPath: data.appendingPathComponent("panorama-360/master-prompt.md").path))
  }

  @Test func thePresetsAreRegisteredOnce() async {
    let plugin = plugin()
    var calls = 0
    var last: [[String: Any]] = []
    let send: PSPresetSender = { presets in
      calls += 1
      last = presets
      return ["type": "ok"]
    }
    await plugin.registerPresets(using: send)
    await plugin.registerPresets(using: send)
    #expect(calls == 1 && last.count == 2)
  }

  @Test func aRefusedRegistrationIsTriedAgain() async {
    let plugin = plugin()
    var answers: [[String: Any]?] = [["type": "error", "text": "The plug-in is not active."], nil, ["type": "ok", "added": 2]]
    var calls = 0
    let send: PSPresetSender = { _ in
      calls += 1
      return answers.removeFirst()
    }
    await plugin.registerPresets(using: send)
    await plugin.registerPresets(using: send)
    await plugin.registerPresets(using: send)
    await plugin.registerPresets(using: send)
    #expect(calls == 3)
  }

  @Test func theProjectMessageOpensTheProjectFolder() async {
    let plugin = plugin()
    let folder = TestImages.tempFolder()
    _ = await plugin.handle(Data(#"{"type":"project","name":"p","folder":"\#(folder.path)","adoptLegacy":false}"#.utf8))
    #expect(plugin.projectFolderForTests?.path == folder.path)
  }

  @Test func theSessionMessagesAreRoutedToTheSeamCorrection() async throws {
    let plugin = plugin()
    let next = await plugin.handle(Data(#"{"type":"session.next","index":1,"count":1}"#.utf8))
    #expect(String(decoding: try #require(next), as: UTF8.self).contains("done"), "no session: nothing to do")
    #expect(await plugin.handle(Data(#"{"type":"session.end","reason":"stopped"}"#.utf8)) == nil)
  }
}
