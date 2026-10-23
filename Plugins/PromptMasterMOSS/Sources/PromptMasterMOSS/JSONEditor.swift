import AppKit
import DTHubDesign
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
    Self.highlight(view)
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
    view.string = text
    Self.highlight(view)
  }

  /// The color of the descriptive texts: teal, a little deeper on a light background so that it reads.
  static let descriptiveColor = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(DS.accent) : NSColor(DS.accentDeep)
  }

  /// Paints the descriptive texts teal and everything else in the plain color. Only attributes change, never the text,
  /// so the caret, the selection and the undo stay as they are.
  static func highlight(_ view: NSTextView) {
    guard let storage = view.textStorage else { return }
    let whole = NSRange(location: 0, length: storage.length)
    storage.beginEditing()
    storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: whole)
    for range in JSONHighlight.descriptiveRanges(in: storage.string) {
      storage.addAttribute(.foregroundColor, value: descriptiveColor, range: range)
    }
    storage.endEditing()
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: JSONEditor
    init(_ parent: JSONEditor) { self.parent = parent }

    func textDidChange(_ notification: Notification) {
      guard let view = notification.object as? NSTextView else { return }
      parent.text = view.string
      JSONEditor.highlight(view)
    }
  }
}

/// Finds the descriptive texts of a caption JSON: the content of the string values of the keys that hold prose.
enum JSONHighlight {
  static let descriptiveKeys: Set<String> = [
    "high_level_description", "aesthetics", "lighting", "photo", "art_style", "medium", "background", "desc", "text",
  ]

  /// UTF-16 ranges of the content (without the quotes) of each string value whose key is descriptive. It scans the
  /// text once and copes with JSON that is broken or half typed: a string that never closes is left alone.
  static func descriptiveRanges(in json: String) -> [NSRange] {
    let units = Array(json.utf16)
    let quote: UInt16 = 0x22, backslash: UInt16 = 0x5C, colon: UInt16 = 0x3A
    var ranges: [NSRange] = []
    var pendingKey: String?   // a key was read and the colon after it too: the next token is its value
    var lastKey: String?      // a string was read and nothing but spaces since
    var index = 0

    func isSpace(_ unit: UInt16) -> Bool { unit == 0x20 || unit == 0x0A || unit == 0x0D || unit == 0x09 }

    while index < units.count {
      let unit = units[index]
      if unit == quote {
        let start = index + 1
        var end = start
        var closed = false
        while end < units.count {
          if units[end] == backslash { end += 2; continue }
          if units[end] == quote { closed = true; break }
          end += 1
        }
        guard closed else { break }
        if let key = pendingKey {
          if descriptiveKeys.contains(key) { ranges.append(NSRange(location: start, length: end - start)) }
          pendingKey = nil
          lastKey = nil
        } else {
          lastKey = String(decoding: units[start..<end], as: UTF16.self)
        }
        index = end + 1
        continue
      }
      if unit == colon, let key = lastKey {
        pendingKey = key
        lastKey = nil
      } else if !isSpace(unit) {
        // Any other character ends what was pending: a key with no string after it, a string that was no key.
        pendingKey = nil
        lastKey = nil
      }
      index += 1
    }
    return ranges
  }
}
