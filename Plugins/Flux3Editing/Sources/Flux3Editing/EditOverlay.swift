import AppKit
import CoreGraphics
import Foundation
import ImageIO

/// Disegna i riquadri sulle immagini che vanno all'LLM (spec «l'LLM vede le immagini»): l'immagine di partenza come la tela di
/// uscita (l'immagine posizionata e ingrandita come nel tab, margini vuoti compresi) o una reference intera, con i box in colori
/// degli elementi e il loro id. Serve a far capire all'LLM quale oggetto è quale id e dove andrà; non è l'immagine di FLUX.3.
enum EditOverlay {
  /// Il colore dei margini della tela dove l'immagine non arriva.
  private static let margin = CGColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 1)

  /// Scrive il PNG in `folder` (`flux3editing-picture-<name>.png`) e ne dà il percorso; nil se l'immagine non si legge.
  static func render(imagePath: String, geometry: StageGeometry, boxes: [OverlayBox], to folder: URL, name: String, maxPixel: Int = 1024) -> String? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: imagePath) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    let aspect = geometry.canvasAspect > 0 ? geometry.canvasAspect : 1
    let (width, height) = aspect >= 1
      ? (maxPixel, max(1, Int((Double(maxPixel) / aspect).rounded()))) : (max(1, Int((Double(maxPixel) * aspect).rounded())), maxPixel)
    guard let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    let (w, h) = (CGFloat(width), CGFloat(height))
    context.setFillColor(margin)
    context.fill(CGRect(x: 0, y: 0, width: w, height: h))
    // Le coordinate sono dall'alto a sinistra; CoreGraphics parte dal basso.
    func rect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect { CGRect(x: x, y: h - y - height, width: width, height: height) }
    let frame = geometry.imageFrame
    context.interpolationQuality = .high
    context.draw(image, in: rect(x: frame.minX * w, y: frame.minY * h, width: frame.width * w, height: frame.height * h))
    let line = max(3, w / 300)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    for item in boxes {
      let grid = CGFloat(BBox.grid)
      let box = rect(
        x: CGFloat(item.box.x0) / grid * w, y: CGFloat(item.box.y0) / grid * h, width: CGFloat(item.box.x1 - item.box.x0) / grid * w,
        height: CGFloat(item.box.y1 - item.box.y0) / grid * h)
      let color = EditPalette.nsColor(index: item.colorIndex)
      context.saveGState()
      context.setStrokeColor(color.cgColor)
      context.setLineWidth(line)
      if item.style != .solid { context.setLineDash(phase: 0, lengths: [line * 3, line * 2]) }
      context.stroke(box.insetBy(dx: line / 2, dy: line / 2))
      context.restoreGState()
      drawLabel(item.caption, color: color, above: box, in: CGSize(width: w, height: h), fontSize: max(14, w / 60), context: context)
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let result = context.makeImage(), let png = NSBitmapImageRep(cgImage: result).representation(using: .png, properties: [:]) else { return nil }
    let safe = String(name.map { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" ? $0 : "_" })
    let url = folder.appendingPathComponent("flux3editing-picture-\(safe).png")
    do { try png.write(to: url) } catch { return nil }
    return url.path
  }

  /// L'etichetta sopra l'angolo in alto a sinistra del riquadro (dentro, se sopra non c'è posto), con lo sfondo del colore dell'elemento.
  private static func drawLabel(_ text: String, color: NSColor, above box: CGRect, in canvas: CGSize, fontSize: CGFloat, context: CGContext) {
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold), .foregroundColor: NSColor.black.withAlphaComponent(0.85),
    ]
    let string = NSAttributedString(string: text, attributes: attributes)
    let size = string.size()
    let (padding, height) = (CGFloat(5), size.height + 4)
    // `box` è in coordinate CoreGraphics (origine in basso): sopra il box è y = box.maxY.
    let aboveY = box.maxY
    let y = aboveY + height <= canvas.height ? aboveY : box.maxY - height
    let x = max(0, min(box.minX, canvas.width - size.width - padding * 2))
    let background = CGRect(x: x, y: y, width: size.width + padding * 2, height: height)
    // Con CoreGraphics e non con `NSColor.setFill`: così il colore resta quello dell'elemento, senza conversioni.
    context.setFillColor(color.cgColor)
    context.addPath(CGPath(roundedRect: background, cornerWidth: 3, cornerHeight: 3, transform: nil))
    context.fillPath()
    string.draw(at: CGPoint(x: x + padding, y: y + 2))
  }
}
