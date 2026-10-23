import DTHubDesign
import SwiftUI

/// La card di destra in basso: gli elementi, una scheda ciascuno (quella nuova si apre da sola), e in fondo Annulla, Scrivi con LLM,
/// Invia.
struct MossElementsCard: View {
  @ObservedObject var state: MossState
  let send: () -> Void
  let write: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      DSPanelHeader(icon: "square.on.square.dashed", title: L.text(.elementsTitle, italian: state.italian))
      VStack(alignment: .leading, spacing: DS.rowGap) {
        ScrollViewReader { reader in
          ScrollView {
            LazyVStack(spacing: 8) {
              if state.document.items.isEmpty {
                Text(L.text(.noElements, italian: state.italian)).font(.caption).foregroundStyle(.secondary)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              ForEach(Array(state.document.items.enumerated()), id: \.element.id) { index, item in
                ItemCard(state: state, item: item, index: index).id(item.id)
              }
            }
          }
          .scrollIndicators(.hidden)
          .onChange(of: state.selectedItem) { _, id in
            if let id { withAnimation { reader.scrollTo(id, anchor: .center) } }
          }
        }
        .frame(minHeight: 140, maxHeight: .infinity)
        buttons
        ForEach(state.statusLines, id: \.self) { line in
          Text(line).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
      }
      .padding(DS.panelPadding)
    }
    .dsPanel()
  }

  private var buttons: some View {
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
  }
}

private struct ItemCard: View {
  @ObservedObject var state: MossState
  let item: MossItem
  let index: Int

  private var excerpt: String {
    let source = item.label == .text && item.caption.isEmpty ? item.text : item.caption
    let line = source.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
    if line.isEmpty { return L.text(.noCaption, italian: state.italian) }
    return line.count > 46 ? String(line.prefix(46)) + "…" : line
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
          .rotationEffect(.degrees(item.expanded ? 90 : 0))
        Text("E\(index + 1) · \(L.name(of: item.label, italian: state.italian).lowercased())")
          .font(.caption.monospaced().weight(.semibold)).foregroundStyle(Color.black.opacity(0.85))
          .padding(.horizontal, 6).padding(.vertical, 1)
          .background(RoundedRectangle(cornerRadius: 5).fill(MossPalette.color(for: item.label)))
        Text(excerpt).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
        Spacer(minLength: 0)
        iconButton("arrow.up", help: L.text(.moveUp, italian: state.italian), enabled: index > 0) { state.moveItem(item.id, by: -1) }
        iconButton("arrow.down", help: L.text(.moveDown, italian: state.italian), enabled: index < state.document.items.count - 1) {
          state.moveItem(item.id, by: 1)
        }
        Button { state.removeItem(item.id) } label: { Image(systemName: "xmark").font(.caption) }
          .buttonStyle(.plain).foregroundStyle(DS.remove).help(L.text(.removeElement, italian: state.italian))
      }
      .padding(10).contentShape(Rectangle())
      .onTapGesture {
        state.update(item: item.id) { $0.expanded.toggle() }
        state.selectedItem = item.id
      }
      if item.expanded { details.padding([.horizontal, .bottom], 10) }
    }
    .background(RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous).fill(Color.primary.opacity(0.06)))
    .overlay(
      RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous)
        .strokeBorder(DS.accent, lineWidth: state.selectedItem == item.id ? 2 : 0))
  }

  private func iconButton(_ name: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: name).font(.caption) }
      .buttonStyle(.plain).foregroundStyle(.secondary).disabled(!enabled).help(help)
  }

  private var details: some View {
    VStack(alignment: .leading, spacing: 8) {
      Picker("", selection: Binding(get: { item.label }, set: { state.setLabel($0, for: item.id) })) {
        ForEach(MossLabel.allCases, id: \.self) { Text(L.name(of: $0, italian: state.italian)).tag($0) }
      }
      .pickerStyle(.segmented).labelsHidden()
      FieldLabel(text: L.text(.captionLabel, italian: state.italian))
      NoteField(
        text: state.itemBinding(item.id, \.caption, fallback: item.caption),
        placeholder: L.text(.captionPlaceholder, italian: state.italian), minHeight: 56, maxHeight: 110)
      if item.label == .text {
        HStack {
          FieldLabel(text: L.text(.textLabel, italian: state.italian))
          Text(L.text(.verbatim, italian: state.italian)).font(.caption).foregroundStyle(.secondary)
        }
        NoteField(
          text: state.itemBinding(item.id, \.text, fallback: item.text),
          placeholder: L.text(.textPlaceholder, italian: state.italian), minHeight: 44, maxHeight: 90)
      }
      FieldLabel(text: L.text(.tagsLabel, italian: state.italian))
      TextField("", text: state.itemBinding(item.id, \.tags, fallback: item.tags))
        .textFieldStyle(.roundedBorder)
      FieldLabel(text: L.text(.position, italian: state.italian))
      PositionField(state: state, item: item)
      FieldLabel(text: L.text(.colorsLabel, italian: state.italian))
      PaletteRow(
        colors: item.colors, limit: Palette.elementLimit, italian: state.italian,
        set: { state.setColor($1, at: $0, in: .item(item.id)) }, remove: { state.removeColor(at: $0, from: .item(item.id)) },
        add: { state.addColor(to: .item(item.id)) })
    }
  }
}

/// La posizione come quattro numeri in pixel dal centro: `y0, x0, y1, x1`. Si tiene appena i numeri si leggono; un testo illeggibile
/// resta com'è, con una riga che spiega cos'è una posizione, e il box resta quello di prima.
private struct PositionField: View {
  @ObservedObject var state: MossState
  let item: MossItem
  @State private var text = ""
  @FocusState private var focused: Bool

  private var canonical: String { state.positionText(of: item.id) }
  private var isUnreadable: Bool {
    guard let size = state.generationSize, size.isUsable else { return false }
    return !text.isEmpty && MossGeometry.parseCentered(text, current: item.box, size: size) == nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      TextField("y0, x0, y1, x1", text: $text)
        .textFieldStyle(.roundedBorder).font(.body.monospaced())
        .focused($focused)
        .disabled(state.generationSize?.isUsable != true)
        .onAppear { text = canonical }
        .onChange(of: text) { _, new in
          if focused { state.setPosition(new, of: item.id) }
        }
        .onChange(of: item.box) { _, _ in
          // Un cambio che non viene da questo campo (il canvas, Annulla, un'altra dimensione): si mostra.
          if !focused { text = canonical }
        }
        .onChange(of: state.generationSize) { _, _ in text = canonical }
        .onChange(of: focused) { _, isFocused in
          if !isFocused && !isUnreadable { text = canonical }
        }
        .onSubmit { if !isUnreadable { text = canonical } }
      if isUnreadable {
        Text(L.text(.positionInvalid, italian: state.italian)).font(.caption).foregroundStyle(DS.remove)
      }
    }
  }
}
