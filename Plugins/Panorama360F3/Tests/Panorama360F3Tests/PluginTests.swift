import Foundation
import Testing

@testable import Panorama360F3

@MainActor
struct PluginTests {
  @Test func theManifestSaysFlux3Only() {
    let manifest = Panorama360F3Plugin().manifest
    #expect(manifest.id == "com.exiztenz.dthub.panorama360f3" && manifest.name == "Pano 360 F3")
    #expect(manifest.symbol == "globe" && manifest.families == ["flux3_5b"])
    #expect(manifest.version == "1.0")
  }

  @Test func anUnknownMessageIsUnsupported() async throws {
    let answer = await Panorama360F3Plugin().handle(Data(#"{"type":"zzz"}"#.utf8))
    #expect(String(decoding: try #require(answer), as: UTF8.self).contains("unsupported"))
  }
}
