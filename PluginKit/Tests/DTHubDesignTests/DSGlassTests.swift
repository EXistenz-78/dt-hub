import AppKit
import SwiftUI
import Testing

@testable import DTHubDesign

/// The look the buttons take on macOS 15, where there is no Liquid Glass: a material, with the tint under it.
@MainActor
@Suite("Glass fallback")
struct DSGlassTests {
  private func render(_ view: some View) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    let image = try #require(renderer.cgImage)
    return NSBitmapImageRep(cgImage: image)
  }

  @Test func aTintedButtonStaysColoured() throws {
    let rep = try render(Color.clear.frame(width: 40, height: 20).modifier(DSGlassFallback(shape: Capsule(), tint: .red)))
    let center = try #require(rep.colorAt(x: 20, y: 10)?.usingColorSpace(.sRGB))
    #expect(center.alphaComponent > 0.5)
    #expect(center.redComponent > center.greenComponent + 0.2 && center.redComponent > center.blueComponent + 0.2)
  }

  @Test func withoutATintItIsDrawnToo() throws {
    let rep = try render(Color.clear.frame(width: 40, height: 20).modifier(DSGlassFallback(shape: Circle(), tint: nil)))
    #expect(rep.pixelsWide == 40 && rep.pixelsHigh == 20)
  }
}
