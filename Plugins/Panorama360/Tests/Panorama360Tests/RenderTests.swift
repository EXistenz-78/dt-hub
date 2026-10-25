import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Panorama360

/// Draws the tab to PNG files to look at (set `PANORAMA360_RENDER_DIR`); without it these tests do nothing.
@MainActor
struct RenderTests {
  static func render(_ view: some View, to dir: String, name: String, width: CGFloat = 1000, height: CGFloat = 800) throws {
    let framed = view.frame(width: width, height: height).background(Color(nsColor: .windowBackgroundColor))
    let renderer = ImageRenderer(content: framed)
    renderer.scale = 2
    let image = try #require(renderer.cgImage)
    let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
  }

  static func sampleState() -> PSState {
    let state = PSState(italian: true)
    let landscape = TestImages.make(180, 120) { x, y in
      y < 60 ? (UInt8(40 + x / 3), UInt8(90 + y), 200, 255) : (UInt8(150 - y / 3), UInt8(120 + x / 5), 90, 255)
    }
    for (yaw, pitch, fov, rot) in [(-35.0, 4.0, 70.0, 0.0), (40.0, -6.0, 55.0, 8.0), (175.0, 12.0, 60.0, -5.0)] {
      let sticker = Sticker(name: "s", file: "s.png", yaw: yaw, pitch: pitch, rot: rot, hfov: fov)
      state.mutate { $0.stickers.append(sticker) }
      state.setImage(landscape, for: sticker.id)
    }
    state.select(state.doc.stickers[0].id)
    return state
  }

  @Test func rendersTheTab() async throws {
    guard let dir = ProcessInfo.processInfo.environment["PANORAMA360_RENDER_DIR"] else { return }
    let state = Self.sampleState()
    state.preview = try state.renderedERP(width: 1024, height: 512)
    try Self.render(PSView(state: state).content, to: dir, name: "tab.png")
  }
}
