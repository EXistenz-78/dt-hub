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

/// Il campo del testo della modifica, con gli automatismi dei segnaposto (`ProseAutocomplete`): `<e` → `<el_`, `<r` →
/// `<ref_image_`, e la prima cifra chiude con `>`.
struct ProseEditor: View {
  @Binding var text: String
  let placeholder: String
  var minHeight: CGFloat = 70
  var maxHeight: CGFloat = 170
  @State private var selection: TextSelection?

  var body: some View {
    ZStack(alignment: .topLeading) {
      TextEditor(text: $text, selection: $selection).font(.body).scrollContentBackground(.hidden).padding(6)
      if text.isEmpty {
        Text(placeholder).foregroundStyle(.tertiary).padding(.horizontal, 11).padding(.vertical, 14).allowsHitTesting(false)
      }
    }
    .frame(minHeight: minHeight, maxHeight: maxHeight)
    .background(RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous).fill(Color.primary.opacity(0.06)))
    .onChange(of: text) { old, new in complete(old: old, new: new) }
  }

  /// La battuta è l'unico carattere in più tra `old` e `new`: si prova ogni posto dove può essere entrato (il primo che
  /// completa vince) e, completato, il cursore va dove dice l'automatismo.
  private func complete(old: String, new: String) {
    let (a, b) = (Array(old), Array(new))
    guard b.count == a.count + 1 else { return }
    var prefix = 0
    while prefix < a.count, a[prefix] == b[prefix] { prefix += 1 }
    for position in 0...prefix {
      guard let completion = ProseAutocomplete.complete(old: old, new: new, caret: position + 1) else { continue }
      text = completion.text
      let index = completion.text.index(completion.text.startIndex, offsetBy: completion.caret)
      selection = TextSelection(insertionPoint: index)
      return
    }
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
