import AppKit
import DTHubPluginKit
import Foundation
import Testing

@testable import Flux3Editing

struct OverlayTests {
  /// Un'immagine di un solo colore (grigio 0.5 se non dice altro).
  private func solid(width: Int, height: Int, gray: Double = 0.5) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("f3e-ov-\(UUID().uuidString).png")
    let rep = try #require(NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor(deviceWhite: gray, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSGraphicsContext.restoreGraphicsState()
    try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    return url
  }

  private func folder() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("f3e-ovout-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func rep(_ path: String) throws -> NSBitmapImageRep { try #require(NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: path)))) }
  private func rgb(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> (Double, Double, Double) {
    let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
    return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
  }
  private func near(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ tolerance: Double = 0.06) -> Bool {
    abs(a.0 - b.0) < tolerance && abs(a.1 - b.1) < tolerance && abs(a.2 - b.2) < tolerance
  }
  /// Il colore di un elemento come lo restituisce `rgb(_:_:_:)`: il PNG scritto è in RGB generico, il confronto in sRGB.
  private func palette(_ index: Int) -> (Double, Double, Double) {
    let c = EditPalette.rgb[index]
    let color = NSColor(colorSpace: .genericRGB, components: [CGFloat(c.0), CGFloat(c.1), CGFloat(c.2), 1], count: 4).usingColorSpace(.sRGB)!
    return (Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent))
  }

  /// Il colore del centro di un file, letto come lo legge il test del risultato (il grigio di un file in RGB di dispositivo cambia in sRGB).
  private func look(of source: URL) throws -> (Double, Double, Double) {
    let r = try #require(NSBitmapImageRep(data: try Data(contentsOf: source)))
    return rgb(r, r.pixelsWide / 2, r.pixelsHigh / 2)
  }

  @Test func aSolidBoxIsDrawnWithTheColorOfItsElement_theInsideStaysTheImage() throws {
    let source = try solid(width: 800, height: 600)
    let out = folder()
    defer { try? FileManager.default.removeItem(at: out); try? FileManager.default.removeItem(at: source) }
    let gray = try look(of: source)
    let box = OverlayBox(id: "el_1", colorIndex: 0, box: BBox(y0: 300, x0: 300, y1: 800, x1: 800), style: .solid)
    let path = try #require(EditOverlay.render(imagePath: source.path, geometry: .plain(image: CGSize(width: 800, height: 600)), boxes: [box], to: out, name: "0"))
    #expect(path.hasPrefix(out.path))
    let picture = try rep(path)
    #expect(picture.pixelsWide == 1024 && picture.pixelsHigh == 768)  // il lato lungo a 1024, le proporzioni dell'immagine
    let left = Int(0.300 * 1024)  // il bordo sinistro del riquadro, in pixel
    let edge = palette(0)
    #expect(near(rgb(picture, left + 1, 450), edge), "il bordo ha il colore dell'elemento")
    #expect(near(rgb(picture, 550, 450), gray), "dentro il riquadro resta l'immagine, senza riempimento")
    #expect(near(rgb(picture, 100, 700), gray), "fuori dal riquadro resta l'immagine")
  }

  @Test func aDashedBoxLeavesGapsInItsBorder() throws {
    let source = try solid(width: 800, height: 600)
    let out = folder()
    defer { try? FileManager.default.removeItem(at: out); try? FileManager.default.removeItem(at: source) }
    let gray = try look(of: source)
    let box = OverlayBox(id: "el_1", colorIndex: 1, box: BBox(y0: 300, x0: 100, y1: 800, x1: 900), style: .dashedFrom)
    let path = try #require(EditOverlay.render(imagePath: source.path, geometry: .plain(image: CGSize(width: 800, height: 600)), boxes: [box], to: out, name: "d"))
    let picture = try rep(path)
    let y = Int(0.800 * 768) - 1  // sul bordo basso
    var colored = 0, plain = 0
    for x in stride(from: Int(0.2 * 1024), to: Int(0.8 * 1024), by: 2) { if near(rgb(picture, x, y), gray, 0.03) { plain += 1 } else { colored += 1 } }
    #expect(colored > 20 && plain > 20, "tratteggio: tratti colorati e vuoti")
  }

  @Test func theLabelSitsAboveTheBoxInTheColorOfTheElement() throws {
    let source = try solid(width: 800, height: 600)
    let out = folder()
    defer { try? FileManager.default.removeItem(at: out); try? FileManager.default.removeItem(at: source) }
    let box = OverlayBox(id: "el_1", colorIndex: 2, box: BBox(y0: 400, x0: 300, y1: 800, x1: 800), style: .solid)
    let path = try #require(EditOverlay.render(imagePath: source.path, geometry: .plain(image: CGSize(width: 800, height: 600)), boxes: [box], to: out, name: "l"))
    let picture = try rep(path)
    let top = Int(0.400 * 768), left = Int(0.300 * 1024)
    #expect(near(rgb(picture, left + 3, top - 5), palette(2)), "l'etichetta ha lo sfondo del colore dell'elemento")
  }

  @Test func theStartPictureIsTheCanvas_theImagePlacedAsInTheTab_theMarginsAreNotTheImage() throws {
    // La tela è 2:1; la finestra mostra l'immagine al 50 % al centro: i quattro margini restano vuoti.
    let source = try solid(width: 800, height: 400, gray: 0.8)
    let out = folder()
    defer { try? FileManager.default.removeItem(at: out); try? FileManager.default.removeItem(at: source) }
    let window = try JSONDecoder().decode(DTHubImageWindow.self, from: Data(#"{"x":-400,"y":-200,"width":1600,"height":800}"#.utf8))
    let imageLook = try look(of: source)
    let geometry = StageGeometry(canvas: CGSize(width: 1024, height: 512), image: CGSize(width: 800, height: 400), window: window)
    let path = try #require(EditOverlay.render(imagePath: source.path, geometry: geometry, boxes: [], to: out, name: "0"))
    let picture = try rep(path)
    #expect(picture.pixelsWide == 1024 && picture.pixelsHigh == 512)
    #expect(near(rgb(picture, 512, 256), imageLook), "al centro c'è l'immagine")
    #expect(!near(rgb(picture, 5, 5), imageLook), "nel margine non c'è l'immagine")
  }

  @Test func aTallCanvasMakesATallPicture_andAnUnreadableImageGivesNothing() throws {
    let source = try solid(width: 300, height: 600)
    let out = folder()
    defer { try? FileManager.default.removeItem(at: out); try? FileManager.default.removeItem(at: source) }
    let path = try #require(EditOverlay.render(imagePath: source.path, geometry: .plain(image: CGSize(width: 300, height: 600)), boxes: [], to: out, name: "t"))
    let picture = try rep(path)
    #expect(picture.pixelsHigh == 1024 && picture.pixelsWide == 512)
    #expect(EditOverlay.render(imagePath: "/nonexistent.png", geometry: .plain(image: CGSize(width: 1, height: 1)), boxes: [], to: out, name: "x") == nil)
  }
}
