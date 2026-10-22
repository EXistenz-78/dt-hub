import AppKit
import SwiftUI

/// La casella della composizione: testo libero in cui gli `<id>` sono evidenziati con il colore dell'elemento (arancione se
/// l'elemento non c'è ancora). Avvisa a ogni modifica e quando perde il fuoco.
struct F3CompositionEditor: NSViewRepresentable {
  @Binding var text: String
  /// Il colore di ogni id (indice nella tavolozza).
  let colors: [String: Int]
  let placeholder: String
  let onChange: (String) -> Void
  let onCommit: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSTextView.scrollableTextView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = false
    guard let view = scroll.documentView as? NSTextView else { return scroll }
    view.delegate = context.coordinator
    view.isRichText = false
    view.drawsBackground = false
    view.font = .systemFont(ofSize: NSFont.systemFontSize)
    view.textContainerInset = NSSize(width: 4, height: 6)
    view.allowsUndo = true
    view.isAutomaticQuoteSubstitutionEnabled = false
    view.isAutomaticDashSubstitutionEnabled = false
    view.string = text
    context.coordinator.highlight(view, colors: colors)
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let view = scroll.documentView as? NSTextView else { return }
    if view.string != text, !view.hasMarkedText() {
      view.string = text
    }
    context.coordinator.highlight(view, colors: colors)
  }

  @MainActor
  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: F3CompositionEditor
    init(_ parent: F3CompositionEditor) { self.parent = parent }

    func textDidChange(_ notification: Notification) {
      guard let view = notification.object as? NSTextView else { return }
      parent.text = view.string
      parent.onChange(view.string)
      highlight(view, colors: parent.colors)
    }

    func textDidEndEditing(_ notification: Notification) { parent.onCommit() }

    func highlight(_ view: NSTextView, colors: [String: Int]) {
      guard let storage = view.textStorage else { return }
      let string = view.string
      let full = NSRange(location: 0, length: (string as NSString).length)
      storage.beginEditing()
      storage.removeAttribute(.backgroundColor, range: full)
      storage.removeAttribute(.foregroundColor, range: full)
      storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
      for match in F3IDParser.ids(in: string) {
        let range = NSRange(match.range, in: string)
        let color = colors[match.id].map { F3Palette.nsColor(index: $0) } ?? NSColor.systemOrange
        storage.addAttribute(.backgroundColor, value: color.withAlphaComponent(colors[match.id] == nil ? 0.25 : 0.85), range: range)
        storage.addAttribute(.foregroundColor, value: colors[match.id] == nil ? NSColor.systemOrange : NSColor.black, range: range)
      }
      storage.endEditing()
    }
  }
}
