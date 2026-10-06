import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PromptMasterI4

/// Draws the tab offscreen, to look at it. With `I4_RENDER_DIR` set the pictures are written there as PNG files;
/// without it the tests only check that something was drawn.
@MainActor
@Suite("The tab on screen")
struct RenderTests {
  /// A state that reads nothing from the user's folders or preferences: the data built into the plug-in and a memory store.
  private func freshState() -> I4State {
    let data = I4Data(database: I4Data.embeddedDatabase, config: I4Data.embeddedConfig, warnings: [])
    return I4State(data: data, store: I4Store(storage: MemoryStorage()), italian: true)
  }

  private func filledState() -> I4State {
    let state = freshState()
    state.active = true
    for id in ["mo_peaceful", "ch_analogous", "ls_neon", "lq_soft_shadows", "fr_medium", "lf_wide_aperture", "fs_film_grain", "bg_blurred"] {
      state.choose(id)
    }
    state.document.description = "Una tavola calda al neon, di notte, con un cliente solo al bancone"
    state.document.background = "la strada bagnata vista dalla finestra"
    for hex in ["#0B1F3A", "#FF2E63", "#08D9D6"] { state.document.addColor(hex) }
    state.toggleOpen(section: "aesthetics")
    state.toggleOpen(category: "ij_mood_merged")
    state.toggleOpen(section: "lighting")
    state.addElement(.obj)
    state.document.updateElement(state.document.elements[0].id) {
      $0.desc = "un cliente solo al bancone con una tazza"
      $0.bbox = BBox(y0: 320, x0: 120, y1: 900, x1: 560)
    }
    state.addElement(.text)
    state.document.updateElement(state.document.elements[1].id) {
      $0.bbox = BBox(y0: 60, x0: 180, y1: 200, x1: 820)
      $0.text = "OPEN ALL NIGHT"
      $0.lettering = "ty_neon_sign"
      $0.desc = "insegna sopra la finestra"
    }
    state.addElement(.obj)
    state.toggleExpanded(state.document.elements[2].id)
    state.update(generationSize: CGSize(width: 1280, height: 832))
    // One sentence already written, one that went out of date.
    let fields = state.fields
    state.document.written["lighting"] = WrittenPhrase(text: "Lit by neon signs.", input: fields.first { $0.id == "lighting" }!.input)
    state.document.written["description"] = WrittenPhrase(text: "A diner.", input: "old")
    state.select(state.document.elements[0].id)
    return state
  }

  private func render(_ state: I4State, dark: Bool, name: String) throws -> NSBitmapImageRep {
    let view = NSHostingView(rootView: I4View(state: state, send: {}, write: {}))
    view.frame = NSRect(x: 0, y: 0, width: 1180, height: 700)
    let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.contentView = view
    view.layoutSubtreeIfNeeded()
    let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: rep)
    if let folder = ProcessInfo.processInfo.environment["I4_RENDER_DIR"], let png = rep.representation(using: .png, properties: [:]) {
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
        let key = UInt32(color.redComponent * 255) << 16 | UInt32(color.greenComponent * 255) << 8 | UInt32(color.blueComponent * 255)
        seen.insert(key)
      }
    }
    return seen.count
  }

  @Test func theTabIsDrawnInLightAndDarkWithAFilledStateAndAnEmptyOne() throws {
    for (state, label) in [(filledState(), "filled"), (freshState(), "empty")] {
      for dark in [false, true] {
        let rep = try render(state, dark: dark, name: "tab-\(label)-\(dark ? "dark" : "light").png")
        #expect(rep.pixelsWide >= 1180 && distinctColors(rep) > 20, "\(label) \(dark)")
      }
    }
  }

  @Test func theJSONEditorLeavesTheQuotesStraightAndTheTextAsTyped() {
    let view = NSTextView()
    JSONEditor.configure(view)
    #expect(!view.isAutomaticQuoteSubstitutionEnabled && !view.isAutomaticDashSubstitutionEnabled)
    #expect(!view.isAutomaticTextReplacementEnabled && !view.isAutomaticSpellingCorrectionEnabled)
    #expect(!view.isRichText && view.allowsUndo)
  }
}
