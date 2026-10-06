import AppKit
import SwiftUI
import Testing

@testable import PromptMasterI4

/// Types into the position field of an element card, in a window that is never on screen (the field editor takes the
/// text as a real keyboard would).
@MainActor
@Suite(.serialized)
struct PositionFieldTests {
  private func textFields(_ view: NSView) -> [NSTextField] {
    ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap(textFields)
  }

  private struct Result {
    var box: [Int]?
    var field: String
  }

  private func type(_ text: String, into type: ElementType = .obj) async throws -> Result {
    let state = I4State(
      data: I4Data(database: I4Data.embeddedDatabase, config: I4Data.embeddedConfig, warnings: []),
      store: I4Store(storage: MemoryStorage()), italian: true)
    state.active = true
    state.addElement(type)
    let view = NSHostingView(rootView: I4View(state: state, send: {}, write: {}))
    let frame = NSRect(x: -30000, y: -30000, width: 1180, height: 1000)
    let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = view
    window.setFrame(frame, display: false)
    window.orderFront(nil)
    view.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(200))
    let field = try #require(textFields(view).first { ($0.placeholderString ?? "").hasPrefix("y0") })
    window.makeFirstResponder(field)
    let editor = try #require(window.fieldEditor(true, for: field) as? NSTextView)
    for character in text {
      editor.insertText(String(character), replacementRange: editor.selectedRange())
      try await Task.sleep(for: .milliseconds(20))
    }
    window.makeFirstResponder(nil)  // leaving the field
    try await Task.sleep(for: .milliseconds(250))
    return Result(box: state.document.elements[0].bbox?.array, field: field.stringValue)
  }

  @Test func aReadablePositionBecomesTheBoxAndTheFieldShowsItWrittenOut() async throws {
    for text in ["100, 100, 600, 600", "100 100 600 600", "[100,100,600,600]"] {
      let result = try await type(text)
      #expect(result.box == [100, 100, 600, 600] && result.field == "[100, 100, 600, 600]", "\(text)")
    }
  }

  @Test func aPositionWithDecimalsIsRounded() async throws {
    let result = try await type("100.5, 100, 600, 600")
    #expect(result.box == [101, 100, 600, 600])
  }

  @Test func aPositionThatCannotBeReadStaysWritten() async throws {
    for text in ["100, 100, 110, 110", "1, 2, 3", "abc"] {
      let result = try await type(text)
      #expect(result.box == nil && result.field == text, "\(text)")
    }
  }
}
