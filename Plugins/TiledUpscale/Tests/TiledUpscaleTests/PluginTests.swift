import Foundation
import Testing

@testable import TiledUpscale

@MainActor
struct PluginTests {
  @Test func theManifestRequiresAnEditModelAndKeepsItsIdentity() {
    let plugin = TiledUpscalePlugin()
    #expect(plugin.manifest.id == "com.exiztenz.dthub.tiledupscale")
    #expect(plugin.manifest.name == "Tiled Upscale")
    #expect(plugin.manifest.requiresEditModel == true)
  }

  @Test func anUnknownMessageIsUnsupportedAndTheKnownOnesAreAnswered() async throws {
    let plugin = TiledUpscalePlugin()
    let unknown = await plugin.handle(Data(#"{"type":"zzz"}"#.utf8))
    #expect(String(decoding: try #require(unknown), as: UTF8.self).contains("unsupported"))
    #expect(await plugin.handle(Data(#"{"type":"activate"}"#.utf8)) == nil)
    let done = await plugin.handle(Data(#"{"type":"session.next","index":1,"count":1}"#.utf8))
    #expect(String(decoding: try #require(done), as: UTF8.self).contains("done"), "no session open: nothing to do")
  }
}
