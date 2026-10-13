import AppKit
import Foundation
import SwiftUI
import Testing

@testable import LoRAAdvisor

/// Draws the tab offscreen, to look at it. With `LA_RENDER_DIR` set the pictures are written there as PNG files;
/// without it the tests only check that something was drawn.
@MainActor
@Suite("The tab on screen")
struct RenderTests {
  private func state(filled: Bool) throws -> LAState {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("la-render-\(UUID().uuidString)", isDirectory: true)
    let store = LAStore(folder: folder)
    let fetcher = FakeFetcher()
    let jobs = LAJobs(store: store, fetcher: fetcher, summarise: { _, _ in nil }, pause: .zero, italian: true)
    let state = LAState(store: store, jobs: jobs, fetcher: fetcher, italian: true)
    guard filled else { return state }
    state.active = true
    let catalog = """
      [{"file":"film.ckpt","name":"Analog Film 35","family":"flux2_9b","trigger":"analogfilm35","weight":0.8},
       {"file":"skin.ckpt","name":"Skin Detail Realism","family":"flux2_9b","trigger":"skindetail","weight":1},
       {"file":"sun.ckpt","name":"SLR · Match the sun","family":"flux2_9b","trigger":"","weight":1},
       {"file":"light.ckpt","name":"Qwen Lightning 8 steps","family":"qwen_image_2.1","trigger":"","weight":1}]
      """
    let context = """
      {"type":"context","tempFolder":"/tmp/x","model":"flux.ckpt","family":"flux2_9b",
       "prompt":"ritratto di una donna anziana in una cucina, luce dalla finestra, pellicola 35 mm",
       "promptGuide":{"label":"FLUX.2 klein","usesNegative":false,"notes":""},
       "languageModels":[{"name":"llm","path":"/x","supportsImages":false}],
       "parameters":{"loras":[{"file":"film.ckpt","weight":0.8,"mode":0,"trigger":"analogfilm35"}]},
       "loraCatalog":\(catalog)}
      """
    state.apply(context: Data(context.utf8))
    let picture = try #require(LAThumbnail.jpeg(from: Pictures.png()))
    store.setThumbnail(picture, manual: false, for: "film.ckpt")
    store.setThumbnail(picture, manual: false, for: "skin.ckpt")
    store.update("film.ckpt") {
      $0.notes = "Grana e resa cromatica da pellicola 35 mm; funziona meglio tra 0,6 e 0,9."
      $0.link = "https://civitai.com/models/1"
      $0.foundBySearch = true
      $0.searched = true
    }
    store.update("skin.ckpt") {
      $0.notes = "Aumenta il dettaglio della pelle (pori, rughe). Parola di attivazione: skindetail."
      $0.link = "https://civitai.com/models/2"
      $0.rawNotes = true
    }
    store.setPageText("page", for: "skin.ckpt")
    store.update("sun.ckpt") { $0.searched = true }
    state.openFile = "skin.ckpt"
    state.setAdvice(
      #"[{"n":1,"weight":0.8,"why":"Dà la grana e i colori della pellicola 35 mm che chiedi."},{"n":2,"weight":0.6,"why":"Rughe e pelle credibili per un volto anziano."}]"#,
      candidates: state.candidates())
    return state
  }

  private func render(_ state: LAState, dark: Bool, name: String) throws -> NSBitmapImageRep {
    let view = NSHostingView(rootView: LAView(state: state))
    view.frame = NSRect(x: 0, y: 0, width: 1180, height: 700)
    let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.contentView = view
    view.layoutSubtreeIfNeeded()
    let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: rep)
    if let folder = ProcessInfo.processInfo.environment["LA_RENDER_DIR"], let png = rep.representation(using: .png, properties: [:]) {
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
    for (filled, label) in [(true, "filled"), (false, "empty")] {
      for dark in [false, true] {
        let rep = try render(try state(filled: filled), dark: dark, name: "tab-\(label)-\(dark ? "dark" : "light").png")
        #expect(rep.pixelsWide >= 1180 && distinctColors(rep) > (filled ? 20 : 3), "\(label) \(dark)")
      }
    }
  }
}
