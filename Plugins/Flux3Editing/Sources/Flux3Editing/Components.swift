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

/// Il campo del testo della modifica (spec §5): un `NSTextView`, perché serve colorare i segnaposto `<id>` del colore del loro
/// elemento senza muovere il cursore e completare `<e` → `<el_`, `<r` → `<ref_image_` e la prima cifra con `>`
/// (`ProseAutocomplete`).
struct ProseEditor: View {
  @Binding var text: String
  let placeholder: String
  /// L'indice del colore di ogni id (`EditState.tagColors`).
  let colors: [String: Int]
  var minHeight: CGFloat = 70
  var maxHeight: CGFloat = 170

  var body: some View {
    ZStack(alignment: .topLeading) {
      ProseTextView(text: $text, colors: colors)
      if text.isEmpty {
        Text(placeholder).foregroundStyle(.tertiary).padding(.horizontal, 11).padding(.vertical, 8).allowsHitTesting(false)
      }
    }
    .frame(minHeight: minHeight, maxHeight: maxHeight)
    .background(RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous).fill(Color.primary.opacity(0.06)))
  }
}

private struct ProseTextView: NSViewRepresentable {
  @Binding var text: String
  let colors: [String: Int]

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSTextView.scrollableTextView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    guard let view = scroll.documentView as? NSTextView else { return scroll }
    view.delegate = context.coordinator
    view.font = Coordinator.font
    view.drawsBackground = false
    view.isRichText = false
    view.allowsUndo = true
    view.textContainerInset = NSSize(width: 6, height: 7)
    view.isAutomaticQuoteSubstitutionEnabled = false
    view.isAutomaticDashSubstitutionEnabled = false
    view.isAutomaticTextReplacementEnabled = false
    view.string = text
    context.coordinator.view = view
    context.coordinator.highlight()
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let view = scroll.documentView as? NSTextView else { return }
    if view.string != text {
      // A change that does not come from typing (Undo, a rewrite): keep the caret where it can.
      let range = view.selectedRange()
      view.string = text
      view.setSelectedRange(NSRange(location: min(range.location, (text as NSString).length), length: 0))
    }
    context.coordinator.highlight()
  }

  @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
    static var font: NSFont { NSFont.preferredFont(forTextStyle: .body) }
    var parent: ProseTextView
    weak var view: NSTextView?

    init(_ parent: ProseTextView) { self.parent = parent }

    func textDidChange(_ notification: Notification) {
      guard let view = notification.object as? NSTextView else { return }
      if parent.text != view.string { parent.text = view.string }
      highlight()
    }

    /// One typed character: `<e`, `<r` and the first digit after `<el_` / `<ref_image_` are completed.
    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
      guard let typed = replacementString, typed.count == 1, range.length == 0, !textView.hasMarkedText() else { return true }
      let old = textView.string as NSString
      let before = old.substring(to: range.location)
      let new = old.replacingCharacters(in: range, with: typed)
      guard let completion = ProseAutocomplete.complete(old: old as String, new: new, caret: before.count + 1) else { return true }
      let (oldChars, newChars) = (Array(old as String), Array(completion.text))
      let start = before.count
      let inserted = String(newChars[start..<(start + newChars.count - oldChars.count)])
      textView.insertText(inserted, replacementRange: range)
      textView.setSelectedRange(NSRange(location: String(newChars[..<completion.caret]).utf16.count, length: 0))
      return false
    }

    /// The tags in the colour of their element (dark letters on it, as on the card); the rest in the normal colour.
    func highlight() {
      guard let view, let storage = view.textStorage else { return }
      let full = NSRange(location: 0, length: storage.length)
      storage.beginEditing()
      storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
      storage.addAttribute(.font, value: Self.font, range: full)
      storage.removeAttribute(.backgroundColor, range: full)
      for span in TagHighlight.spans(in: storage.string, colors: parent.colors) {
        if let index = span.colorIndex {
          storage.addAttribute(.backgroundColor, value: EditPalette.nsColor(index: index), range: span.range)
          storage.addAttribute(.foregroundColor, value: NSColor.black.withAlphaComponent(0.85), range: span.range)
        } else {
          storage.addAttribute(.backgroundColor, value: NSColor.secondaryLabelColor.withAlphaComponent(0.25), range: span.range)
        }
      }
      storage.endEditing()
      view.typingAttributes = [.font: Self.font, .foregroundColor: NSColor.labelColor]
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
