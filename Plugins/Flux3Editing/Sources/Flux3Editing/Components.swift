import AppKit
import DTHubDesign
import ImageIO
import SwiftUI

/// Un campo di testo su più righe con un segnaposto, nell'aspetto dell'app.
struct NoteField: View {
  @Binding var text: String
  let placeholder: String
  var minHeight: CGFloat = 70
  var maxHeight: CGFloat = 170

  var body: some View {
    ZStack(alignment: .topLeading) {
      TextEditor(text: $text).font(.body).scrollContentBackground(.hidden).padding(6)
      if text.isEmpty {
        Text(placeholder).foregroundStyle(.tertiary).padding(.horizontal, 11).padding(.vertical, 14).allowsHitTesting(false)
      }
    }
    .frame(minHeight: minHeight, maxHeight: maxHeight)
    .background(RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous).fill(Color.primary.opacity(0.06)))
  }
}

/// Una piccola didascalia sopra un campo.
struct FieldLabel: View {
  let text: String
  var body: some View {
    Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
  }
}

/// L'immagine di un file, ridotta (le tele non ne hanno bisogno in grandezza piena).
enum ImageLoader {
  static func thumbnail(path: String, maxPixel: Int = 1400) -> NSImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
  }
}
