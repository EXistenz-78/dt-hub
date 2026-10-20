import DTHubDesign
import SwiftUI

/// La card 4: gli elementi, una scheda per id (chiuse; quella nuova si apre da sola), e in fondo Annulla, Scrivi con LLM, Invia.
struct F3ElementsCard: View {
  @ObservedObject var state: F3State
  let send: () -> Void
  let write: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "square.on.square.dashed", title: "4 · " + L.text(.elementsTitle, italian: state.italian))
      VStack(alignment: .leading, spacing: DS.rowGap) {
        ScrollViewReader { reader in
          ScrollView {
            LazyVStack(spacing: 8) {
              if state.document.elements.isEmpty {
                Text(L.text(.noElements, italian: state.italian)).font(.caption).foregroundStyle(.secondary)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              ForEach(Array(state.document.elements.enumerated()), id: \.element.id) { index, element in
                ElementCard(state: state, element: element, index: index).id(element.id)
              }
            }
          }
          .scrollIndicators(.hidden)
          .onChange(of: state.selectedElement) { _, id in
            if let id { withAnimation { reader.scrollTo(id, anchor: .center) } }
          }
        }
        .frame(minHeight: 140, maxHeight: .infinity)
        HStack(spacing: DS.controlGap) {
          Button { state.undo() } label: {
            HStack(spacing: DS.pillIconGap) {
              Image(systemName: "arrow.uturn.backward")
              Text(L.text(.undo, italian: state.italian))
            }
          }
          .buttonStyle(DSPillButtonStyle())
          .disabled(!state.canUndo)
          Button(action: write) {
            HStack(spacing: DS.pillIconGap) {
              if state.isWriting {
                ProgressView().controlSize(.small)
                Text(L.text(.writing, italian: state.italian))
              } else {
                Image(systemName: "sparkles")
                Text(L.text(.writeWithLLM, italian: state.italian))
              }
            }
          }
          .buttonStyle(DSPillButtonStyle())
          .disabled(!state.canWrite)
          Spacer(minLength: 0)
          Button(action: send) {
            HStack(spacing: DS.pillIconGap) {
              if state.isSending {
                ProgressView().controlSize(.small)
                Text(L.text(.sending, italian: state.italian))
              } else {
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
  }
}

private struct ElementCard: View {
  @ObservedObject var state: F3State
  let element: F3Element
  let index: Int

  private var excerpt: String {
    let line = element.desc.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
    if line.isEmpty { return L.text(.noDescription, italian: state.italian) }
    return line.count > 46 ? String(line.prefix(46)) + "…" : line
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
          .rotationEffect(.degrees(element.expanded ? 90 : 0))
        Text(element.id).font(.caption.monospaced().weight(.semibold)).foregroundStyle(Color.black.opacity(0.85))
          .padding(.horizontal, 6).padding(.vertical, 1)
          .background(RoundedRectangle(cornerRadius: 5).fill(F3Palette.color(index: element.colorIndex)))
        Text(excerpt).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
        Spacer(minLength: 0)
        iconButton("arrow.up", help: L.text(.moveUp, italian: state.italian), enabled: index > 0) { state.moveElement(element.id, by: -1) }
        iconButton("arrow.down", help: L.text(.moveDown, italian: state.italian), enabled: index < state.document.elements.count - 1) {
          state.moveElement(element.id, by: 1)
        }
        Button { state.removeElement(element.id) } label: { Image(systemName: "xmark").font(.caption) }
          .buttonStyle(.plain).foregroundStyle(DS.remove).help(L.text(.removeElement, italian: state.italian))
      }
      .padding(10).contentShape(Rectangle())
      .onTapGesture {
        state.update(element: element.id) { $0.expanded.toggle() }
        state.selectedElement = element.id
      }
      if element.expanded { details.padding([.horizontal, .bottom], 10) }
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

  private var details: some View {
    VStack(alignment: .leading, spacing: 8) {
      NoteField(
        text: Binding(get: { element.desc }, set: { value in state.update(element: element.id) { $0.desc = value } }),
        placeholder: L.text(.elementPlaceholder, italian: state.italian), minHeight: 56, maxHeight: 110)
      FieldLabel(text: L.text(.position, italian: state.italian))
      BBoxField(
        box: Binding(get: { element.box }, set: { value in state.update(element: element.id) { $0.box = value } }),
        italian: state.italian)
    }
  }
}

/// Il box come quattro numeri: `y0, x0, y1, x1`. Si tiene appena i numeri si leggono; un testo illeggibile resta com'è, con una
/// riga che spiega cos'è una posizione, e il box resta quello di prima.
private struct BBoxField: View {
  @Binding var box: BBox
  let italian: Bool
  @State private var text = ""
  @FocusState private var focused: Bool

  private var isUnreadable: Bool { BBox.isUnreadable(text) }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      TextField("y0, x0, y1, x1", text: $text)
        .textFieldStyle(.roundedBorder).font(.body.monospaced())
        .focused($focused)
        .onAppear { text = box.text }
        .onChange(of: text) { _, new in
          if let parsed = BBox.parse(new), parsed != box { box = parsed }
        }
        .onChange(of: box) { _, new in
          // Un cambio che non viene da questo campo (il canvas, Annulla): si mostra.
          if !isUnreadable && BBox.parse(text) != new { text = new.text }
        }
        .onChange(of: focused) { _, isFocused in
          if !isFocused && !isUnreadable { text = box.text }
        }
        .onSubmit { if !isUnreadable { text = box.text } }
      if isUnreadable {
        Text(L.text(.positionInvalid, italian: italian)).font(.caption).foregroundStyle(DS.remove)
      }
    }
  }
}
