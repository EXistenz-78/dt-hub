import Foundation
import Testing

@testable import Panorama360F3

struct PFModelsTests {
  @Test func panoStateRoundTripsThroughJSON() throws {
    var state = PanoState()
    state.images = [
      PFImage(name: "a.png", file: "images/a.png"),
      PFImage(name: "b.png", file: "images/b.png", visible: false),
    ]
    state.description = "foggy cemetery"
    state.size = PFSize(width: 2176, height: 1088)
    state.viewerOpen = true
    let decoded = try JSONDecoder().decode(PanoState.self, from: JSONEncoder().encode(state))
    #expect(decoded == state)
    #expect(decoded.images[1].visible == false)
  }

  @Test func aStateWithoutNewKeysDecodesWithDefaults() throws {
    let decoded = try JSONDecoder().decode(PanoState.self, from: Data(#"{"version":1}"#.utf8))
    #expect(decoded.images.isEmpty)
    #expect(decoded.size == PFSize(width: 2048, height: 1024))
    #expect(decoded.viewerOpen == false)
    #expect(decoded.description == "")
  }
}
