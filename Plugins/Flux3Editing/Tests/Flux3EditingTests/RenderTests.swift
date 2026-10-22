import AppKit
import DTHubPluginKit
import Foundation
import SwiftUI
import Testing

@testable import Flux3Editing

/// Disegna il tab fuori schermo, per guardarlo. Con `F3E_RENDER_DIR` i PNG vanno in quella cartella; senza, i test controllano
/// solo che qualcosa sia stato disegnato.
@MainActor
@Suite("Il tab a schermo")
struct RenderTests {
  /// Un PNG di prova con un gradiente e un rettangolo.
  private func picture(_ name: String, width: Int, height: Int, hue: CGFloat) throws -> String {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("f3e-\(UUID().uuidString)-\(name)")
    let rep = try #require(NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGradient(starting: NSColor(hue: hue, saturation: 0.5, brightness: 0.8, alpha: 1), ending: NSColor(hue: hue, saturation: 0.7, brightness: 0.3, alpha: 1))?
      .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 60)
    NSColor.white.withAlphaComponent(0.7).setFill()
    NSRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2).fill()
    NSGraphicsContext.restoreGraphicsState()
    try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    return url.path
  }

  private func filledState() throws -> EditState {
    let state = EditState(store: EditStore(storage: MemoryStorage()), italian: true)
    state.active = true
    let start = try picture("start.png", width: 1200, height: 900, hue: 0.55)
    let a = try picture("a.png", width: 900, height: 1200, hue: 0.05), b = try picture("b.png", width: 1000, height: 1000, hue: 0.3)
    let json =
      #"{"type":"context","tempFolder":"/t","startImage":"\#(start)","moodboard":["\#(a)","\#(b)"],"parameters":{"width":2048,"height":1664},"startImageWindow":{"x":0,"y":-60,"width":1200,"height":1020}}"#
    state.update(context: try JSONDecoder().decode(DTHubContext.self, from: Data(json.utf8)))
    state.document.prose = "Modifica <ref_image_0> aggiungendo <lamp_1> da <ref_image_1>. Sposta <chair_1>."
    state.drawOnReference(BBox(y0: 250, x0: 250, y1: 750, x1: 750))
    state.rename("el_1", to: "lamp_1")
    state.update(element: "lamp_1") { $0.desc = "Una lampada da tavolo." }
    state.showReference(by: 1)
    state.drawOnReference(BBox(y0: 100, x0: 100, y1: 400, x1: 400))
    state.drawOnCanvas(BBox(y0: 500, x0: 100, y1: 800, x1: 300))
    state.rename("el_2", to: "chair_1")
    state.document.setKind(.move, of: "chair_1")
    state.drawOnCanvas(BBox(y0: 100, x0: 600, y1: 300, x1: 900))
    state.document.setKind(.remove, of: "el_2")
    state.select("lamp_1")
    return state
  }

  private func render(_ state: EditState, dark: Bool, name: String) throws -> NSBitmapImageRep {
    let view = NSHostingView(rootView: EditView(state: state, send: {}, write: {}))
    view.frame = NSRect(x: 0, y: 0, width: 1180, height: 1000)
    let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.contentView = view
    window.orderFrontRegardless()
    view.layoutSubtreeIfNeeded()
    // The pictures load in the background: give them a moment.
    RunLoop.current.run(until: Date().addingTimeInterval(0.8))
    view.layoutSubtreeIfNeeded()
    let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: rep)
    if let folder = ProcessInfo.processInfo.environment["F3E_RENDER_DIR"], let png = rep.representation(using: .png, properties: [:]) {
      try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
      try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name))
    }
    return rep
  }

  private func distinctColors(_ rep: NSBitmapImageRep) -> Int {
    var seen = Set<UInt32>()
    for x in stride(from: 0, to: rep.pixelsWide, by: 7) {
      for y in stride(from: 0, to: rep.pixelsHigh, by: 7) {
        guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
        seen.insert(UInt32(color.redComponent * 255) << 16 | UInt32(color.greenComponent * 255) << 8 | UInt32(color.blueComponent * 255))
      }
    }
    return seen.count
  }

  @Test func theTabIsDrawnInLightAndDarkFilledAndEmpty() throws {
    let empty = EditState(store: EditStore(storage: MemoryStorage()), italian: true)
    for (state, label) in [(try filledState(), "filled"), (empty, "empty")] {
      for dark in [false, true] {
        let rep = try render(state, dark: dark, name: "tab-\(label)-\(dark ? "dark" : "light").png")
        #expect(rep.pixelsWide >= 1180 && distinctColors(rep) > 20, "\(label) \(dark)")
      }
    }
  }

  @Test func theFilledStateHasThePairsTheCanvasAndTheCorrectProportions() throws {
    let state = try filledState()
    #expect(state.document.elements.map(\.kind) == [.fromReference, .fromReference, .move, .remove])
    #expect(state.startGeometry.canvasAspect == 2048.0 / 1664.0)
    #expect(state.referenceGeometry(of: state.refs[0]).canvasAspect == 0.75)
    #expect(state.referenceGeometry(of: state.refs[1]).canvasAspect == 1)
    // The pair of a reference shares its color between the two stages.
    let pair = state.document.elements[0]
    #expect(state.canvasItems.first { $0.elementID == pair.id }?.colorIndex == pair.colorIndex)
    #expect(state.arrows.count == 1)
  }

  @Test func theWindowMovesTheImageInsideTheCanvas() throws {
    let state = try filledState()
    let frame = state.startGeometry.imageFrame
    #expect(frame.minY > 0 && abs(frame.width - 1) < 1e-9)  // y = −60 in a 1020-tall window: the image sits lower, margins above
  }
}
