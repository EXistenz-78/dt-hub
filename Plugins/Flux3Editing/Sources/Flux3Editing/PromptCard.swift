import DTHubDesign
import SwiftUI

/// La card Prompt: il testo, le mini-card dei riquadri, e in fondo Annulla, Scrivi con LLM e Invia.
struct PromptCard: View {
  @ObservedObject var state: EditState
  let send: () -> Void
  let write: () -> Void
  @State private var confirmClear = false

  var body: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "text.alignleft", title: L.text(.promptTitle, italian: state.italian))
      VStack(alignment: .leading, spacing: DS.rowGap) {
        FieldLabel(text: L.text(.proseTitle, italian: state.italian))
        ProseEditor(
          text: Binding(get: { state.document.prose }, set: { state.document.prose = $0 }),
          placeholder: "", colors: state.tagColors, minHeight: 64, maxHeight: 120)
        Text(L.text(.proseHint, italian: state.italian)).font(.caption).foregroundStyle(.secondary)
        if state.document.elements.isEmpty {
          Text(L.text(.noElements, italian: state.italian)).font(.caption).foregroundStyle(.secondary)
        }
        ScrollView {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 10, alignment: .top)], spacing: 10) {
            ForEach(Array(state.document.elements.enumerated()), id: \.element.id) { index, element in
              ElementCard(state: state, element: element, index: index)
            }
          }
        }
        .scrollIndicators(.hidden).frame(minHeight: 120, maxHeight: 360)
        buttons
        lines
      }
      .padding(DS.panelPadding)
    }
    .dsPanel()
    .confirmationDialog(L.text(.clearTitle, italian: state.italian), isPresented: $confirmClear) {
      Button(L.text(.clearAction, italian: state.italian), role: .destructive) { state.clear() }
    }
  }

  private var buttons: some View {
    VStack(alignment: .leading, spacing: DS.controlGap) {
      if state.canSendImages {
        Toggle(
          isOn: Binding(get: { state.document.sendsImages }, set: { state.document.llmImages = $0 })
        ) { Text(L.text(.sendImages, italian: state.italian)).font(.callout) }
        .toggleStyle(DSCheckboxToggleStyle()).help(L.text(.sendImagesHelp, italian: state.italian))
      }
      actionRow
    }
  }

  private var actionRow: some View {
    HStack(spacing: DS.controlGap) {
      Button { state.undo() } label: {
        HStack(spacing: DS.pillIconGap) {
          Image(systemName: "arrow.uturn.backward")
          Text(L.text(.undo, italian: state.italian))
        }
      }
      .buttonStyle(DSPillButtonStyle()).disabled(!state.canUndo)
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
      .buttonStyle(DSPillButtonStyle()).disabled(!state.canWrite)
      Spacer(minLength: 0)
      Button { confirmClear = true } label: { Image(systemName: "trash") }
        .buttonStyle(DSPillButtonStyle()).disabled(!state.canClear || state.isWriting || state.isSending)
        .help(L.text(.clearHelp, italian: state.italian))
        .accessibilityLabel(L.text(.clearHelp, italian: state.italian))
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
      .buttonStyle(DSPillButtonStyle(prominent: true)).disabled(!state.canSend)
    }
  }

  private var lines: some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(Array(state.problemLines.enumerated()), id: \.offset) { _, line in
        Text(line).font(.caption).foregroundStyle(DS.remove)
      }
      ForEach(Array(state.warningLines.enumerated()), id: \.offset) { _, line in
        Text(line).font(.caption).foregroundStyle(.secondary)
      }
      if !state.status.isEmpty { Text(state.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
    }
  }
}

/// La mini-card di un riquadro: id, tipo, da dove, coordinate e descrizione.
private struct ElementCard: View {
  @ObservedObject var state: EditState
  let element: EditElement
  let index: Int

  private var isMissing: Bool { EditComposer.isMissing(element, refs: state.refs) }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        IDField(id: element.id, placeholder: L.text(.idLabel, italian: state.italian)) { state.rename(element.id, to: $0) }
          .background(RoundedRectangle(cornerRadius: 5).fill(EditPalette.color(index: element.colorIndex)))
        kindMenu
        Spacer(minLength: 0)
        icon("arrow.up", help: L.text(.moveUp, italian: state.italian), enabled: index > 0) { state.document.moveElement(element.id, by: -1) }
        icon("arrow.down", help: L.text(.moveDown, italian: state.italian), enabled: index < state.document.elements.count - 1) {
          state.document.moveElement(element.id, by: 1)
        }
        Button {
          state.document.delete(element.id)
          if state.selected == element.id { state.selected = nil }
        } label: { Image(systemName: "xmark").font(.caption) }
        .buttonStyle(.plain).foregroundStyle(DS.remove).help(L.text(.removeElement, italian: state.italian))
      }
      Text(verbatim: "from: \(fromText) · \(coordinates)").font(.caption.monospaced()).foregroundStyle(.secondary)
      if isMissing { Text(L.text(.imageGone, italian: state.italian)).font(.caption).foregroundStyle(DS.remove) }
      // The text is read from the state, not from the copy of the element this card was drawn with: a stale copy hands the
      // editor the old text between two keystrokes and the cursor jumps to the end.
      NoteField(
        text: Binding(
          get: { state.document.element(element.id)?.desc ?? element.desc },
          set: { value in state.update(element: element.id) { $0.desc = value } }),
        placeholder: L.text(.descriptionPlaceholder, italian: state.italian), minHeight: 52, maxHeight: 100)
    }
    .padding(10)
    .background(RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous).fill(Color.primary.opacity(0.06)))
    .overlay(
      RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous)
        .strokeBorder(DS.accent, lineWidth: state.selected == element.id ? 2 : 0)
    )
    .contentShape(Rectangle())
    .onTapGesture { state.select(element.id) }
  }

  private var fromText: String {
    switch element.kind {
    case .fromReference: return element.refFile.flatMap { RefNumbering.number(ofFile: $0, in: state.refs) }.map { "ref_image_\($0)" } ?? "?"
    case .new: return "null"
    default: return "ref_image_0"
    }
  }

  private var coordinates: String {
    func text(_ box: BBox?) -> String { box.map(\.text) ?? "null" }
    switch element.kind {
    case .new: return "src_bbox null · tgt_bbox \(text(element.tgt))"
    case .existing: return "src_bbox = tgt_bbox \(text(element.src))"
    case .remove: return "src_bbox \(text(element.src)) · tgt_bbox null"
    default: return "src_bbox \(text(element.src)) · tgt_bbox \(text(element.tgt))"
    }
  }

  @ViewBuilder private var kindMenu: some View {
    if element.kind == .fromReference {
      pill(L.text(.kindFromReference, italian: state.italian))
    } else {
      Menu {
        ForEach([EditKind.new, .existing, .move, .remove], id: \.self) { kind in
          Button(title(kind)) { state.document.setKind(kind, of: element.id) }
        }
      } label: { pill(title(element.kind) + " ▾") }
      .menuStyle(.button).buttonStyle(.plain).fixedSize()
    }
  }

  private func title(_ kind: EditKind) -> String {
    switch kind {
    case .fromReference: return L.text(.kindFromReference, italian: state.italian)
    case .new: return L.text(.kindNew, italian: state.italian)
    case .existing: return L.text(.kindExisting, italian: state.italian)
    case .move: return L.text(.kindMove, italian: state.italian)
    case .remove: return L.text(.kindRemove, italian: state.italian)
    }
  }

  private func pill(_ text: String) -> some View {
    Text(text).font(.caption.weight(.semibold)).lineLimit(1).fixedSize().padding(.horizontal, 9).padding(.vertical, 3)
      .background(Capsule().fill(Color.primary.opacity(0.12)))
  }

  private func icon(_ name: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: name).font(.caption) }
      .buttonStyle(.plain).foregroundStyle(.secondary).disabled(!enabled).help(help)
  }
}

/// L'id di un elemento: si scrive in una copia locale e si conferma a Invio o quando il campo perde il fuoco. Cambiare l'id a
/// ogni lettera cambierebbe l'identità della scheda e il campo perderebbe il fuoco a ogni battuta.
private struct IDField: View {
  let id: String
  let placeholder: String
  let commit: (String) -> Void
  @State private var text = ""
  @FocusState private var focused: Bool

  var body: some View {
    TextField(placeholder, text: $text)
      .textFieldStyle(.plain).font(.caption.monospaced().weight(.semibold)).foregroundStyle(Color.black.opacity(0.85))
      .padding(.horizontal, 6).padding(.vertical, 2).frame(width: 118)
      .focused($focused)
      .onAppear { text = id }
      .onChange(of: id) { _, new in if !focused { text = new } }
      .onChange(of: focused) { _, isFocused in if !isFocused { commit(text) } }
      .onSubmit { commit(text) }
  }
}
