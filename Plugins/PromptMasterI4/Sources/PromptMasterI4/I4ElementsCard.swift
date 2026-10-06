import AppKit
import DTHubDesign
import SwiftUI

/// The right card: the elements, one card each (closed at first), and the buttons: add, review the JSON, send.
struct I4ElementsCard: View {
  @ObservedObject var state: I4State
  let send: () -> Void
  let write: () -> Void
  @State private var reviewing = false

  var body: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "square.on.square.dashed", title: L.text(.elements, italian: state.italian))
      VStack(alignment: .leading, spacing: DS.rowGap) {
        ScrollViewReader { reader in
          ScrollView {
            LazyVStack(spacing: 8) {
              ForEach(Array(state.document.elements.enumerated()), id: \.element.id) { index, element in
                ElementCard(state: state, element: element, number: index + 1).id(element.id)
              }
            }
          }
          .scrollIndicators(.hidden)
          // A box drawn on the canvas, or a click on one, brings its card into view.
          .onChange(of: state.selectedElement) { _, id in
            if let id { withAnimation { reader.scrollTo(id, anchor: .center) } }
          }
        }
        .frame(minHeight: 140, maxHeight: .infinity)
        HStack(spacing: DS.controlGap) {
          addButton(.obj, key: .addObject, icon: "cube")
          addButton(.text, key: .addText, icon: "textformat")
        }
        LLMTable(state: state)
        if state.hasEditedJSON {
          HStack(spacing: 8) {
            Text(L.text(.jsonEdited, italian: state.italian)).font(.caption).foregroundStyle(DS.remove)
            Button(L.text(.restore, italian: state.italian)) { state.restoreJSON() }
              .buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(DS.accent)
          }
        }
        HStack(spacing: DS.controlGap) {
          Button { reviewing = true } label: {
            HStack(spacing: DS.pillIconGap) {
              Image(systemName: "doc.text.magnifyingglass")
              Text(L.text(.reviewJSON, italian: state.italian))
            }
          }
          .buttonStyle(DSPillButtonStyle())
          Button(action: write) {
            if state.isWriting {
              HStack(spacing: DS.pillIconGap) {
                ProgressView().controlSize(.small)
                Text(L.text(.writing, italian: state.italian))
              }
            } else {
              HStack(spacing: DS.pillIconGap) {
                Image(systemName: "sparkles")
                Text(L.text(.writeWithLLM, italian: state.italian))
              }
            }
          }
          .buttonStyle(DSPillButtonStyle())
          .disabled(!state.canWrite)
          Spacer(minLength: 0)
          Button(action: send) {
            if state.isSending {
              HStack(spacing: DS.pillIconGap) {
                ProgressView().controlSize(.small)
                Text(L.text(.sending, italian: state.italian))
              }
            } else {
              HStack(spacing: DS.pillIconGap) {
                Image(systemName: "paperplane")
                Text(L.text(.send, italian: state.italian))
              }
            }
          }
          .buttonStyle(DSPillButtonStyle(prominent: true))
          .disabled(!state.canSend)
        }
        if !state.status.isEmpty {
          Text(state.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
      }
      .padding(DS.panelPadding)
    }
    .dsPanel()
    .sheet(isPresented: $reviewing) { JSONSheet(state: state, close: { reviewing = false }) }
  }
}

extension I4ElementsCard {
  /// «Add an object» / «Add a text»: the type of a new element is chosen here, not on its card.
  fileprivate func addButton(_ type: ElementType, key: L.Key, icon: String) -> some View {
    Button { state.addElement(type) } label: {
      HStack(spacing: DS.pillIconGap) {
        Image(systemName: icon)
        Text(L.text(key, italian: state.italian))
      }
    }
    .buttonStyle(DSPillButtonStyle())
  }
}

private struct ElementCard: View {
  @ObservedObject var state: I4State
  let element: I4Element
  let number: Int

  private var isOpen: Bool { state.expandedElements.contains(element.id) }

  private var excerpt: String {
    let source = element.type == .text ? element.text : element.desc
    let empty = L.text(element.type == .text ? .emptyText : .noDescription, italian: state.italian)
    let line = source.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
    if line.isEmpty { return empty }
    return line.count > 46 ? String(line.prefix(46)) + "…" : line
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
          .rotationEffect(.degrees(isOpen ? 90 : 0))
        Text("E\(number)").font(.caption.monospaced().weight(.semibold))
          .padding(.horizontal, 6).padding(.vertical, 1)
          .background(RoundedRectangle(cornerRadius: 5).fill(element.type == .text ? Color.yellow.opacity(0.35) : DS.accent.opacity(0.35)))
        Text(excerpt).font(.callout).lineLimit(1).truncationMode(.tail)
        Spacer(minLength: 0)
        if element.bbox == nil {
          Text(L.text(.noPosition, italian: state.italian)).font(.caption2).foregroundStyle(DS.remove)
        }
        iconButton("arrow.up", help: L.text(.moveUp, italian: state.italian), enabled: number > 1) {
          state.document.moveElement(element.id, by: -1)
        }
        iconButton("arrow.down", help: L.text(.moveDown, italian: state.italian), enabled: number < state.document.elements.count) {
          state.document.moveElement(element.id, by: 1)
        }
        Button { state.removeElement(element.id) } label: { Image(systemName: "xmark").font(.caption) }
          .buttonStyle(.plain).foregroundStyle(DS.remove).help(L.text(.removeElement, italian: state.italian))
      }
      .padding(10).contentShape(Rectangle())
      .onTapGesture {
        state.toggleExpanded(element.id)
        state.select(element.id)
      }
      if isOpen { details.padding([.horizontal, .bottom], 10) }
    }
    .background(RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous).fill(Color.primary.opacity(0.06)))
    .overlay(
      RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous)
        .strokeBorder(DS.accent, lineWidth: state.selectedElement == element.id ? 2 : 0))
  }

  private func iconButton(_ name: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: name).font(.caption) }
      .buttonStyle(.plain).foregroundStyle(.secondary).disabled(!enabled).help(help)
  }

  private func binding<T>(_ keyPath: WritableKeyPath<I4Element, T>) -> Binding<T> {
    Binding(
      get: { element[keyPath: keyPath] },
      set: { value in state.document.updateElement(element.id) { $0[keyPath: keyPath] = value } })
  }

  private var details: some View {
    VStack(alignment: .leading, spacing: 8) {
      NoteField(
        text: binding(\.desc),
        placeholder: L.text(element.type == .text ? .textPlaceholder : .objectPlaceholder, italian: state.italian),
        minHeight: 56, maxHeight: 110)
      if element.type == .text {
        FieldLabel(text: L.text(.lettering, italian: state.italian))
        Picker("", selection: Binding(get: { element.lettering ?? "" }, set: { value in
          state.document.updateElement(element.id) { $0.lettering = value.isEmpty ? nil : value }
        })) {
          Text(L.text(.none, italian: state.italian)).tag("")
          ForEach(state.catalog.lettering) { Text(state.italian ? $0.it : $0.en).tag($0.id) }
        }
        .labelsHidden()
        FieldLabel(text: L.text(.printedText, italian: state.italian))
        TextField(L.text(.printedTextPlaceholder, italian: state.italian), text: binding(\.text)).textFieldStyle(.roundedBorder)
      }
      FieldLabel(text: L.text(.position, italian: state.italian))
      BBoxField(box: binding(\.bbox), italian: state.italian)
      FieldLabel(text: L.text(.palette, italian: state.italian))
      PaletteRow(
        colors: element.colors, limit: Palette.elementLimit, italian: state.italian,
        set: { index, hex in state.document.setElementColor(element.id, at: index, to: hex) },
        remove: { index in state.document.removeElementColor(element.id, at: index) },
        add: { state.addColor(toElement: element.id) })
    }
  }
}

/// The box as four numbers: `y0, x0, y1, x1`. It is kept as soon as the numbers can be read (no Return needed); an empty
/// field means no position. Text that cannot be read is never wiped: it stays as written, with a line that says what a
/// position is, and the box stays what it was. Leaving the field with a readable text writes the box out in full.
private struct BBoxField: View {
  @Binding var box: BBox?
  let italian: Bool
  @State private var text = ""
  @FocusState private var focused: Bool

  private var isUnreadable: Bool { BBox.isUnreadable(text) }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      TextField(L.text(.positionPlaceholder, italian: italian), text: $text)
        .textFieldStyle(.roundedBorder).font(.body.monospaced())
        .focused($focused)
        .onAppear { text = box?.text ?? "" }
        .onChange(of: text) { _, new in
          let resolved = BBox.resolve(new, current: box)
          if resolved != box { box = resolved }
        }
        .onChange(of: box) { _, new in
          // A change that did not come from this field (the canvas, an undo): show it.
          if !isUnreadable && BBox.resolve(text, current: new) != new { text = new?.text ?? "" }
        }
        .onChange(of: focused) { _, isFocused in
          if !isFocused && !isUnreadable { text = box?.text ?? "" }
        }
        .onSubmit { if !isUnreadable { text = box?.text ?? "" } }
      if isUnreadable {
        Text(L.text(.positionInvalid, italian: italian)).font(.caption).foregroundStyle(DS.remove)
      }
    }
  }
}

/// The window with the JSON: a text anyone can copy and change by hand.
private struct JSONSheet: View {
  @ObservedObject var state: I4State
  let close: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "doc.text", title: L.text(.reviewJSON, italian: state.italian))
      VStack(alignment: .leading, spacing: DS.rowGap) {
        JSONEditor(text: Binding(get: { state.jsonText }, set: { state.editJSON($0) }))
          .background(RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous).fill(Color.primary.opacity(0.06)))
          .frame(minHeight: 360)
        HStack(spacing: DS.controlGap) {
          if state.hasEditedJSON { Text(L.text(.jsonEdited, italian: state.italian)).font(.caption).foregroundStyle(DS.remove) }
          Spacer(minLength: 0)
          Button(L.text(.copy, italian: state.italian)) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(state.jsonText, forType: .string)
          }
          .buttonStyle(DSPillButtonStyle())
          Button(L.text(.restore, italian: state.italian)) { state.restoreJSON() }
            .buttonStyle(DSPillButtonStyle()).disabled(!state.hasEditedJSON)
          Button(L.text(.close, italian: state.italian), action: close).buttonStyle(DSPillButtonStyle(prominent: true))
        }
      }
      .padding(DS.panelPadding)
    }
    .frame(minWidth: 640, minHeight: 480)
  }
}

/// «What the LLM gets»: every field with its state, the sentence that goes in the caption and, for a field that needs a
/// sentence, the raw text that goes there now. Closed at first.
private struct LLMTable: View {
  @ObservedObject var state: I4State
  @State private var isOpen = false

  private func label(_ field: FieldState) -> String {
    switch field {
    case .empty: return L.text(.stateEmpty, italian: state.italian)
    case .raw: return L.text(.stateRaw, italian: state.italian)
    case .written: return L.text(.stateWritten, italian: state.italian)
    case .stale: return L.text(.stateStale, italian: state.italian)
    }
  }

  private func color(_ field: FieldState) -> Color {
    switch field {
    case .written: return DS.accent
    case .stale: return DS.remove
    default: return Color.secondary
    }
  }

  var body: some View {
    let fields = state.fields
    let pending = fields.filter(\.needsWriting).count
    VStack(alignment: .leading, spacing: 6) {
      Button { isOpen.toggle() } label: {
        HStack(spacing: 6) {
          Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            .rotationEffect(.degrees(isOpen ? 90 : 0))
          Text(L.text(.llmTable, italian: state.italian)).font(.subheadline.weight(.semibold))
          Spacer(minLength: 0)
          if pending > 0 {
            Text("\(pending)").font(.caption.weight(.semibold)).monospacedDigit()
              .padding(.horizontal, 7).padding(.vertical, 1).background(Capsule().fill(DS.remove.opacity(0.25)))
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      if isOpen {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(fields) { field in
            VStack(alignment: .leading, spacing: 1) {
              HStack(spacing: 6) {
                Text("<\(field.tag)>").font(.caption.monospaced()).foregroundStyle(.secondary)
                Text(label(field.state)).font(.caption2.weight(.semibold)).foregroundStyle(color(field.state))
                  .padding(.horizontal, 6).padding(.vertical, 1)
                  .background(Capsule().fill(color(field.state).opacity(0.18)))
              }
              if !field.value.isEmpty {
                Text(field.value).font(.caption).foregroundStyle(.primary).lineLimit(3).textSelection(.enabled)
              }
            }
          }
        }
        .padding(.leading, 15)
      }
    }
  }
}
