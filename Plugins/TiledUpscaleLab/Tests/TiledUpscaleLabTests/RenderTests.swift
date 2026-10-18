import AppKit
import Foundation
import SwiftUI
import Testing

@testable import TiledUpscaleLab

/// Draws the tab to PNG files to look at (set `TILEDUPSCALE_RENDER_DIR`); without it these tests do nothing.
@MainActor
struct RenderTests {
  @Test func rendersTheTabBeforeAndDuringAJob() async throws {
    guard let dir = ProcessInfo.processInfo.environment["TILEDUPSCALE_RENDER_DIR"] else { return }
    let state = TUState(store: TUStore(folder: nil), italian: true)
    state.family = "flux2_9b"
    state.active = true
    state.tempFolder = NSTemporaryDirectory()
    state.setImage(TestImages.solid(1300, 900, (220, 120, 60), right: (60, 120, 220), splitX: 650), name: "foto.png")
    func render(_ name: String, width: CGFloat = 1000, height: CGFloat = 900) throws {
      let view = TUView(state: state, actions: .none).frame(width: width, height: height).background(Color(nsColor: .windowBackgroundColor))
      let renderer = ImageRenderer(content: view)
      renderer.scale = 2
      let image = try #require(renderer.cgImage)
      try TUImage.pngData(image)?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
    }
    try render("before.png")
    // Three tiles back.
    await state.prepare(confirmed: true, contribute: { _ in ["type": "ok"] }, registerPreset: { _ in nil })
    var previous: String?
    let plan = try #require(state.plan)
    let folder = TestImages.temporaryFolder()
    for index in 1...3 {
      let tile = plan.tiles[index - 1].rect
      var message = #"{"type":"session.next","index":\#(index),"count":\#(plan.count)"#
      if let previous { message += #","previous":{"path":"\#(previous)","width":\#(plan.tiles[index - 2].rect.width),"height":\#(plan.tiles[index - 2].rect.height)}"# }
      message += "}"
      _ = await state.sessionNext(Data(message.utf8))
      let url = TestImages.write(TestImages.solid(tile.width, tile.height, (40, 200, UInt8(80 * index))), in: folder, name: "r\(index).png")
      previous = url.path
    }
    _ = await state.sessionNext(Data(#"{"type":"session.next","index":4,"count":\#(plan.count),"previous":{"path":"\#(previous!)","width":\#(plan.tiles[2].rect.width),"height":\#(plan.tiles[2].rect.height)}}"#.utf8))
    try render("during.png")
    
  }
}

/// The tab must draw in every state the sliders can leave it in, also when there is no room for the fade (SwiftUI stops the
/// whole app on a slider whose step is larger than its range).
@MainActor
struct SliderStatesTests {
  private func draws(_ state: TUState) -> Bool {
    let view = TUView(state: state, actions: .none).frame(width: 900, height: 900)
    let renderer = ImageRenderer(content: view)
    return renderer.cgImage != nil
  }

  @Test func theTabDrawsWithNoRoomForTheFade() {
    let state = TUState(store: TUStore(folder: nil), italian: false)
    state.maskFree = 256
    #expect(state.fadeRange == 0...0)
    #expect(draws(state))
  }

  @Test func theTabDrawsAtTheExtremesOfEverySlider() {
    for (free, blur, outset) in [(0, 0.0, 0), (256, 30.0, 100), (200, 15.0, 50), (250, 1.0, 1)] {
      let state = TUState(store: TUStore(folder: nil), italian: false)
      state.maskFree = free
      state.maskBlur = blur
      state.maskOutset = outset
      state.junctionFade = state.fadeRange.upperBound
      #expect(draws(state), "free \(free) blur \(blur) outset \(outset)")
      state.overlap = .wide
      #expect(draws(state))
    }
  }
}
