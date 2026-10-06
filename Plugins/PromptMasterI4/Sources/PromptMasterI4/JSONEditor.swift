import AppKit
import SwiftUI

/// The text of the JSON, for editing by hand. A SwiftUI `TextEditor` would turn straight quotes into curly ones as the
/// user types and break the JSON, so this is a plain `NSTextView` with every substitution off.
struct JSONEditor: NSViewRepresentable {
  @Binding var text: String

  /// A text view that leaves what is typed exactly as typed.
  static func configure(_ view: NSTextView) {
    view.isRichText = false
    view.allowsUndo = true
    view.isAutomaticQuoteSubstitutionEnabled = false
    view.isAutomaticDashSubstitutionEnabled = false
    view.isAutomaticTextReplacementEnabled = false
    view.isAutomaticSpellingCorrectionEnabled = false
    view.isContinuousSpellCheckingEnabled = false
    view.isAutomaticLinkDetectionEnabled = false
    view.isAutomaticDataDetectionEnabled = false
    view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    view.textColor = .labelColor
    view.drawsBackground = false
    view.textContainerInset = NSSize(width: 6, height: 6)
  }

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSTextView.scrollableTextView()
    scroll.drawsBackground = false
    guard let view = scroll.documentView as? NSTextView else { return scroll }
    Self.configure(view)
    view.delegate = context.coordinator
    view.string = text
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
    view.string = text
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: JSONEditor
    init(_ parent: JSONEditor) { self.parent = parent }

    func textDidChange(_ notification: Notification) {
      guard let view = notification.object as? NSTextView else { return }
      parent.text = view.string
    }
  }
}
