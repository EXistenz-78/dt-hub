import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PromptMasterMOSS

/// Disegna il tab fuori schermo, per guardarlo. Con `MOSS_RENDER_DIR` impostata i disegni si scrivono là come PNG; senza, i test
/// controllano solo che qualcosa sia stato disegnato.
@MainActor
@Suite("The tab on screen")
struct RenderTests {
  /// Uno stato che non legge niente dalle cartelle o dalle preferenze dell'utente: i dati incorporati e un deposito in memoria.
  private func freshState() -> MossState {
    let data = MossData(database: MossData.embeddedDatabase, config: MossData.embeddedConfig, warnings: [])
    return MossState(data: data, store: MossStore(storage: MemoryStorage()), italian: true)
  }

  private func filledState() -> MossState {
    let state = freshState()
    state.active = true
    state.update(generationSize: PixelSize(width: 1024, height: 640))
    state.document.description = "Una ragazza in kimono rosso in una foresta di bambù"
    for (category, index) in [("photo_genre", 0), ("light_source", 0), ("render_quality", 0)] {
      state.choose(state.data.database.categories.first { $0.id == category }!.terms[index].id)
    }
    state.addFreeMeta("poster")
    state.document.palette = ["#2F4F4F", "#B22222"]
    let boxes: [(MossLabel, String, FracBox)] = [
      (.panel, "sfondo di bambù", FracBox(x0: 0, y0: 0, x1: 1, y1: 1)),
      (.subject, "una ragazza in kimono rosso", FracBox(x0: 0.32, y0: 0.23, x1: 0.68, y1: 1)),
      (.character, "capelli raccolti", FracBox(x0: 0.37, y0: 0.31, x1: 0.63, y1: 1)),
      (.object, "un ombrello di carta", FracBox(x0: 0.15, y0: 0.05, x1: 0.78, y1: 0.52)),
      (.text, "scritta bianca in basso a sinistra", FracBox(x0: 0.04, y0: 0.84, x1: 0.29, y1: 0.95)),
    ]
    for (label, caption, box) in boxes {
      state.addItem(label: label, box: box)
      state.update(item: state.document.items.last!.id) { $0.caption = caption }
    }
    state.update(item: 5) {
      $0.text = "Kyoto\nArashiyama"
      $0.tags = "lettering"
      $0.colors = ["#FFFFFF"]
    }
    state.selectedItem = 2
    state.toggleOpen(group: "D")
    return state
  }

  private func render(_ state: MossState, dark: Bool, name: String) throws -> NSBitmapImageRep {
    let view = NSHostingView(rootView: MossView(state: state, send: {}, write: {}))
    view.frame = NSRect(x: 0, y: 0, width: 1180, height: 760)
    let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.contentView = view
    view.layoutSubtreeIfNeeded()
    let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: rep)
    if let folder = ProcessInfo.processInfo.environment["MOSS_RENDER_DIR"], let png = rep.representation(using: .png, properties: [:]) {
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

  @Test func aChangedShapeOfTheGenerationShowsTheNoticeAndTheTabStillDraws() throws {
    let state = filledState()
    state.update(generationSize: PixelSize(width: 1024, height: 1024))
    #expect(state.sizeNotice != nil)
    let rep = try render(state, dark: false, name: "tab-notice-light.png")
    #expect(distinctColors(rep) > 20)
  }

  @Test func theTypeMenuIsDrawnOverTheCanvas() throws {
    let state = filledState()
    state.typeMenuItem = 2
    let rep = try render(state, dark: true, name: "tab-menu-dark.png")
    #expect(distinctColors(rep) > 20)
  }
}
