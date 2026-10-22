import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PromptMasterF3

/// Disegna il tab fuori schermo, per guardarlo. Con `F3_RENDER_DIR` i PNG vanno in quella cartella; senza, i test controllano
/// solo che qualcosa sia stato disegnato.
@MainActor
@Suite("Il tab a schermo")
struct RenderTests {
  private func freshState() -> F3State {
    let data = F3Data(database: F3Data.embeddedDatabase, config: F3Data.embeddedConfig, warnings: [])
    return F3State(
      data: data, promptFolder: F3Prompts.folder(dataFolder: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
      store: F3Store(storage: MemoryStorage()), italian: true)
  }

  private func filledState() -> F3State {
    let state = freshState()
    state.active = true
    state.document.description = "Una fotografia editoriale di una donna in una strada piovosa di Tokyo, di notte"
    state.toggleOpen(group: "B")
    state.toggleOpen(category: "light_source")
    if let light = state.catalog.categories(mode: .photo).first(where: { $0.id == "light_source" }) { state.choose(light.terms[0].id) }
    state.update(generationSize: CGSize(width: 1536, height: 1024))
    state.compositionChanged("La scena contiene una donna <woman_1>, un ombrello rosso <umbrella_1>, insegne al neon <neon_1> e una lampada <lamp_1> accanto a un'altra <lamp_1>")
    state.commitComposition()
    state.update(element: "woman_1") { $0.desc = "Una giovane donna con un trench nero, in piedi."; $0.box = BBox(y0: 250, x0: 350, y1: 850, x1: 650) }
    state.update(element: "umbrella_1") { $0.desc = "Un ombrello rosso trasparente."; $0.expanded = false }
    state.selectedElement = "woman_1"
    return state
  }

  private func render(_ state: F3State, dark: Bool, name: String) throws -> NSBitmapImageRep {
    let view = NSHostingView(rootView: F3View(state: state, send: {}, write: {}))
    view.frame = NSRect(x: 0, y: 0, width: 1180, height: 760)
    let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.contentView = view
    view.layoutSubtreeIfNeeded()
    let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: rep)
    if let folder = ProcessInfo.processInfo.environment["F3_RENDER_DIR"], let png = rep.representation(using: .png, properties: [:]) {
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
    for (state, label) in [(filledState(), "filled"), (freshState(), "empty")] {
      for dark in [false, true] {
        let rep = try render(state, dark: dark, name: "tab-\(label)-\(dark ? "dark" : "light").png")
        #expect(rep.pixelsWide >= 1180 && distinctColors(rep) > 20, "\(label) \(dark)")
      }
    }
  }

  @Test func filledStateHasTheDuplicateWarningAndFiveBoxesWorthOfElements() {
    let state = filledState()
    #expect(state.duplicateIDs == ["lamp_1"])
    #expect(state.document.elements.count == 4)
  }
}
