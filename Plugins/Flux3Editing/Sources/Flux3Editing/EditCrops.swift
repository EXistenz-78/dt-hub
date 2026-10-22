import AppKit
import Foundation
import ImageIO

/// Un ritaglio da mandare all'LLM: l'immagine di un riquadro disegnato sul Moodboard, per l'elemento `elementID`.
struct EditAttachment: Equatable, Sendable {
  var elementID: String
  var path: String
}

/// I ritagli (spec §7): la parte dell'immagine che un riquadro indica, ridotta, scritta in PNG nella cartella temporanea.
enum EditCrops {
  /// Il ritaglio di `box` (griglia 0–1000, `[y0, x0, y1, x1]`) dell'immagine `path`, con il lato maggiore al massimo `maxPixel`.
  /// Nil se l'immagine non si legge. Il nome del file viene da `name`, ripulito.
  static func crop(path: String, box: BBox, to folder: URL, name: String, maxPixel: Int = 768) -> String? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    let (w, h) = (Double(image.width), Double(image.height))
    let rect = CGRect(
      x: (Double(box.x0) / Double(BBox.grid) * w).rounded(), y: (Double(box.y0) / Double(BBox.grid) * h).rounded(),
      width: (Double(box.x1 - box.x0) / Double(BBox.grid) * w).rounded(), height: (Double(box.y1 - box.y0) / Double(BBox.grid) * h).rounded())
    guard rect.width >= 1, rect.height >= 1, let cropped = image.cropping(to: rect) else { return nil }
    var result = cropped
    let longest = max(cropped.width, cropped.height)
    if longest > maxPixel {
      let scale = Double(maxPixel) / Double(longest)
      let (nw, nh) = (max(1, Int((Double(cropped.width) * scale).rounded())), max(1, Int((Double(cropped.height) * scale).rounded())))
      guard let context = CGContext(
        data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0,
        space: cropped.colorSpace ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return nil }
      context.interpolationQuality = .high
      context.draw(cropped, in: CGRect(x: 0, y: 0, width: nw, height: nh))
      guard let scaled = context.makeImage() else { return nil }
      result = scaled
    }
    let safe = String(name.map { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" ? $0 : "_" })
    let url = folder.appendingPathComponent("flux3editing-crop-\(safe).png")
    guard let png = NSBitmapImageRep(cgImage: result).representation(using: .png, properties: [:]) else { return nil }
    do { try png.write(to: url) } catch { return nil }
    return url.path
  }
}
